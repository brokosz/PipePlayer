import Testing
import Foundation
@testable import PipePlayer

@MainActor
struct PlaybackEngineTests {

    private func voice(timeSignature: String, tempo: Double, displayTempoScaleFactor: Double = 1.0) -> Voice {
        let tune = Tune(
            title: "T", composer: nil, tempo: tempo, timeSignature: timeSignature,
            parts: [TunePart(measures: [Measure(notes: [NoteEvent(pitch: .b, duration: 0.5, embellishment: nil)])])]
        )
        return Voice(id: "melody", name: "Melody", tune: tune, displayTempoScaleFactor: displayTempoScaleFactor)
    }

    @Test func displayTempoHalvesActualTempoUnderCutTime() {
        let engine = PlaybackEngine()
        engine.load(voices: [voice(timeSignature: "2/2", tempo: 160, displayTempoScaleFactor: 2.0)])
        #expect(engine.tempo == 160)
        #expect(engine.displayTempo == 80)
    }

    @Test func displayTempoMatchesActualTempoOutsideCutTime() {
        let engine = PlaybackEngine()
        engine.load(voices: [voice(timeSignature: "4/4", tempo: 90)])
        #expect(engine.tempo == 90)
        #expect(engine.displayTempo == 90)
    }

    @Test func settingDisplayTempoUnderCutTimeDoublesActualTempo() {
        let engine = PlaybackEngine()
        engine.load(voices: [voice(timeSignature: "2/2", tempo: 160, displayTempoScaleFactor: 2.0)])
        engine.displayTempo = 100
        #expect(engine.tempo == 200)
    }

    @Test func displayTempoDividesByFactorForCompoundMeter() {
        // A jig's actual playback tempo is quarter-note-equivalent (198),
        // scaled up 1.5x by BWWParser from the written dotted-quarter value
        // (132) — the display should undo exactly that, not a flat halving.
        let engine = PlaybackEngine()
        engine.load(voices: [voice(timeSignature: "6/8", tempo: 198, displayTempoScaleFactor: 1.5)])
        #expect(engine.displayTempo == 132)
    }

    @Test func instrumentProgramPersistsAcrossInstances() {
        let defaults = UserDefaults.standard
        let key = "PipePlayer.instrumentProgram"
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        let first = PlaybackEngine()
        first.instrumentProgram = 42

        let second = PlaybackEngine()
        #expect(second.instrumentProgram == 42)
    }

    @Test func missingCustomSoundFontFileIsNotRestored() {
        // A saved path from a previous session might no longer exist (file
        // moved/deleted) — restoring should fall back to the built-in bank
        // rather than pointing at a dead path.
        let defaults = UserDefaults.standard
        let key = "PipePlayer.customSoundFontPath"
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.set("/tmp/definitely-does-not-exist-\(UUID().uuidString).sf2", forKey: key)
        let engine = PlaybackEngine()
        #expect(engine.customSoundFontURL == nil)
    }

    @Test func droneTogglesAcrossFullPlaybackLifecycleWithoutCrashing() {
        // No public seam to assert the actual startNote/stopNote(36, ...)
        // calls reached the sampler (would need a mockable instrument
        // abstraction, out of scope here) — this exercises play, toggling
        // mid-playback, seek, pause, stop, and a loop restart with the
        // drone on, confirming those code paths (play/pause/stop/seek/
        // handleFinished's loop branch) don't crash or leave state broken.
        let engine = PlaybackEngine()
        engine.load(voices: [voice(timeSignature: "4/4", tempo: 90)])
        engine.isDroneEnabled = true
        engine.play()
        #expect(engine.state == .playing)
        engine.isDroneEnabled = false
        engine.isDroneEnabled = true
        engine.seek(to: 0)
        engine.pause()
        #expect(engine.state == .paused)
        engine.play()
        engine.stop()
        #expect(engine.state == .stopped)
    }

    @Test func scaledEventsLeavesNoteOnVelocityAtFullScale() {
        let events = [ScheduledMIDIEvent(time: 0, kind: .noteOn, note: 69, velocity: 100)]
        let result = PlaybackEngine.scaledEvents(events, velocityScale: 1.0)
        #expect(result == events)
    }

    @Test func scaledEventsAppliesHarmonyVoiceScaleToNoteOnOnly() {
        let events = [
            ScheduledMIDIEvent(time: 0, kind: .noteOn, note: 69, velocity: 100),
            ScheduledMIDIEvent(time: 1, kind: .noteOff, note: 69, velocity: 0)
        ]
        let result = PlaybackEngine.scaledEvents(events, velocityScale: PlaybackEngine.harmonyVoiceVelocityScale)
        #expect(result[0].velocity == 70) // 100 * 0.7
        #expect(result[1].velocity == 0)  // note-off untouched
    }

    @Test func primaryVoicePlaysAtFullVelocityRegardlessOfVoiceCount() {
        // Primary (voices[0]) always plays at its own full velocity, no
        // matter how many voices are loaded — an earlier version also
        // scaled the melody down by 1/sqrt(activeVoiceCount) to keep the
        // combined ensemble level in check, but that meant the melody was
        // never actually at full volume in a multi-voice tune (down ~42%
        // with 3 voices) — reported as "overall volume is down a lot" even
        // with every volume control maxed. Harmony voices stay tempered by
        // harmonyVoiceVelocityScale alone; the combined level genuinely
        // being louder with more parts playing is expected, not a bug.
        // Distinct pitches per voice let the resulting merged event list be
        // matched back to which voice each note-on actually came from.
        func singleNoteVoice(id: String, pitch: Pitch) -> Voice {
            let tune = Tune(
                title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
                parts: [TunePart(measures: [Measure(notes: [NoteEvent(pitch: pitch, duration: 1, embellishment: nil)])])]
            )
            return Voice(id: id, name: id, tune: tune)
        }
        let primary = singleNoteVoice(id: "melody", pitch: .highA)
        let harm1 = singleNoteVoice(id: "harm1", pitch: .lowA)
        let harm2 = singleNoteVoice(id: "harm2", pitch: .lowG)

        let engine = PlaybackEngine()
        engine.load(voices: [primary, harm1, harm2])

        let noteOns = engine.events.filter { $0.kind == .noteOn }
        let melodyVelocity = noteOns.first { $0.note == Pitch.highA.rawValue }?.velocity
        let harm1Velocity = noteOns.first { $0.note == Pitch.lowA.rawValue }?.velocity
        let harm2Velocity = noteOns.first { $0.note == Pitch.lowG.rawValue }?.velocity

        #expect(melodyVelocity == MIDIEventBuilder.defaultVelocity)
        #expect(harm1Velocity == 70)
        #expect(harm2Velocity == 70)
    }

    @Test func voicesGetDistinctMIDIChannelsSoUnisonsDontDuckTheMelody() {
        // Regression: with a single shared reference-count keyed only by
        // pitch, a harmony voice claiming a pitch first (its note-on
        // processed before the melody's own note-on for that same pitch)
        // would suppress the melody's note-on entirely — "already
        // sounding" — leaving the shared pitch audible at the harmony's
        // lower velocity for the whole overlap. Real harmony arrangements
        // unison often, since the chanter only has 9 notes. Each voice must
        // get its own MIDI channel so this can't happen — verified here by
        // having melody and harmony share the exact same pitch.
        func singleNoteVoice(id: String) -> Voice {
            let tune = Tune(
                title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
                parts: [TunePart(measures: [Measure(notes: [NoteEvent(pitch: .lowA, duration: 1, embellishment: nil)])])]
            )
            return Voice(id: id, name: id, tune: tune)
        }
        let engine = PlaybackEngine()
        engine.load(voices: [singleNoteVoice(id: "melody"), singleNoteVoice(id: "harm1")])

        let noteOns = engine.events.filter { $0.kind == .noteOn && $0.note == Pitch.lowA.rawValue }
        #expect(noteOns.count == 2) // both voices' note-ons survive, none suppressed
        #expect(Set(noteOns.map(\.channel)).count == 2) // on distinct channels
        #expect(noteOns.contains { $0.velocity == MIDIEventBuilder.defaultVelocity }) // melody unaffected
        #expect(noteOns.contains { $0.velocity == 70 }) // harmony still scaled down
    }

    @Test func mutingHarmonyVoicesLeavesMelodyVelocityUnchanged() {
        func singleNoteVoice(id: String, pitch: Pitch) -> Voice {
            let tune = Tune(
                title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
                parts: [TunePart(measures: [Measure(notes: [NoteEvent(pitch: pitch, duration: 1, embellishment: nil)])])]
            )
            return Voice(id: id, name: id, tune: tune)
        }
        let primary = singleNoteVoice(id: "melody", pitch: .highA)
        let harm1 = singleNoteVoice(id: "harm1", pitch: .lowA)
        let harm2 = singleNoteVoice(id: "harm2", pitch: .lowG)

        let engine = PlaybackEngine()
        engine.load(voices: [primary, harm1, harm2])
        engine.setVoiceMuted(id: "harm1", muted: true)
        engine.setVoiceMuted(id: "harm2", muted: true)

        let melodyVelocity = engine.events.first { $0.kind == .noteOn && $0.note == Pitch.highA.rawValue }?.velocity
        #expect(melodyVelocity == MIDIEventBuilder.defaultVelocity)
    }
}
