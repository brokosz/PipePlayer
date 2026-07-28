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
}
