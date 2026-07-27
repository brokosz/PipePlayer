import Foundation

/// A single scheduled MIDI note on/off, with an absolute offset in seconds
/// from the start of the tune.
struct ScheduledMIDIEvent: Equatable {
    enum Kind: Equatable { case noteOn, noteOff }
    var time: TimeInterval
    var kind: Kind
    var note: UInt8
    var velocity: UInt8
}

/// Walks a `Tune` in play order — unrolling repeats and first/second endings —
/// and produces one flat, time-sorted list of note on/off events. This flat
/// list is the single source of truth that both the local sampler and the
/// MIDI-out path consume, so they can never drift relative to each other.
enum MIDIEventBuilder {

    static let defaultVelocity: UInt8 = 100

    /// - Parameter tempoOverride: beats-per-minute to use instead of the
    ///   tune's own tempo (for the UI's tempo slider); pass nil to use the
    ///   tune's tempo as parsed.
    static func buildEvents(for tune: Tune, tempoOverride: Double? = nil) -> [ScheduledMIDIEvent] {
        let expanded = EmbellishmentExpander.expand(tune: tune)
        let bpm = tempoOverride ?? expanded.tempo
        let secondsPerBeat = 60.0 / max(bpm, 1)

        var events: [ScheduledMIDIEvent] = []
        var cursor: TimeInterval = 0

        // A tied note is a single continuous sound spanning two or more
        // written notes (BWW's only way to express a dotted rhythm — see
        // BWWParser), so a chain of tied notes gets exactly one note-on and
        // one note-off, not an independent note-on per note in the chain
        // (which would otherwise produce an audible micro-retrigger on
        // essentially every dotted note in the piece).
        var openNotePitch: UInt8?

        func closeOpenNote(at time: TimeInterval) {
            if let pitch = openNotePitch {
                events.append(ScheduledMIDIEvent(time: time, kind: .noteOff, note: pitch, velocity: 0))
                openNotePitch = nil
            }
        }

        for part in expanded.parts {
            let passes = part.hasRepeat ? [1, 2] : [1]
            for pass in passes {
                for measure in part.measures {
                    if !measure.endingNumbers.isEmpty && !measure.endingNumbers.contains(pass) {
                        continue // e.g. skip a first-ending measure on the repeat pass
                    }
                    for note in measure.notes {
                        let durationSeconds = note.duration * secondsPerBeat * (note.isDotted ? 1.5 : 1.0)
                        if note.isRest {
                            closeOpenNote(at: cursor)
                        } else {
                            let pitch = UInt8(note.pitch.rawValue)
                            if openNotePitch != pitch {
                                // Not a continuation of an open tie (either
                                // nothing was open, or the parser's tie
                                // pitches didn't actually match — defensively
                                // close the stale one and start fresh).
                                closeOpenNote(at: cursor)
                                events.append(ScheduledMIDIEvent(time: cursor, kind: .noteOn, note: pitch, velocity: defaultVelocity))
                                openNotePitch = pitch
                            }
                            if !note.isTiedToNext {
                                closeOpenNote(at: cursor + durationSeconds)
                            }
                        }
                        cursor += durationSeconds
                    }
                }
            }
        }
        closeOpenNote(at: cursor) // defensive: close a chain left dangling by a truncated tie at the very end

        return events.sorted { $0.time < $1.time }
    }

    static func totalDuration(of events: [ScheduledMIDIEvent]) -> TimeInterval {
        events.map(\.time).max() ?? 0
    }
}
