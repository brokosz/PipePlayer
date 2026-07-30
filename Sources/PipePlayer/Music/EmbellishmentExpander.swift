import Foundation

/// Expands a decorated `NoteEvent` into the flat sequence of actual notes
/// (grace notes + melody note) that should be scheduled for playback/MIDI.
///
/// Grace notes borrow their time from the melody note they decorate — every
/// recognized ornament is realized as its exact grace pitches (from
/// `BWWEmbellishmentTable`, transcribed from a real BWW-compatible app's own
/// source) each held for a brief duration, followed by the melody note at
/// its written duration *minus* however much was borrowed. An unrecognized
/// token gets the most conservative treatment: a single High G grace note,
/// so a tune never fails to play over one obscure ornament.
///
/// Borrowing (rather than adding new, un-notated time) matters at the
/// whole-tune level, not just per-note: confirmed against a real, heavily-
/// ornamented hornpipe (174 grace-decorated notes) where adding kept the
/// stated tempo and the actual audible speed in sync per-note, but drifted
/// the *whole tune*'s real playback time noticeably behind what its stated
/// tempo implied (measured effective tempo ~84 against a stated 90) purely
/// from accumulated un-notated grace time. Capped at half the main note's
/// own duration — a very short note under a big ornament still needs to
/// sound like a distinct note afterward, not vanish under its own graces;
/// only that (rare) leftover still adds real time, same as before.
///
/// Real piping ornaments are played essentially as instantaneous "cuts,"
/// snappier than a plain short note — so grace notes here are short in an
/// absolute sense (`graceDuration`), and for long figures (a 7-note
/// crunluath, 10-note piobaireachd throws) the per-note duration additionally
/// shrinks to keep the whole ornament under `maxTotalGraceDuration`, rather
/// than letting note count stretch it out audibly.
enum EmbellishmentExpander {

    static let graceDuration = 0.035
    static let maxTotalGraceDuration = 0.16

    static func expand(_ note: NoteEvent) -> [NoteEvent] {
        guard !note.isRest, let embellishment = note.embellishment else { return [note] }
        guard case .token(let token) = embellishment else { return [note] }

        let gracePitches = BWWEmbellishmentTable.gracePitches(for: token) ?? [.highG]
        guard !gracePitches.isEmpty else { return [note] }
        let perNoteDuration = min(graceDuration, maxTotalGraceDuration / Double(gracePitches.count))

        func grace(_ pitch: Pitch) -> NoteEvent {
            NoteEvent(pitch: pitch, duration: perNoteDuration, embellishment: nil)
        }
        func main() -> NoteEvent {
            var n = note
            n.embellishment = nil
            let totalGraceDuration = perNoteDuration * Double(gracePitches.count)
            let borrowed = min(totalGraceDuration, note.duration * 0.5)
            n.duration = note.duration - borrowed
            return n
        }

        return gracePitches.map(grace) + [main()]
    }

    /// Expands every note across an entire tune, in play order.
    static func expand(tune: Tune) -> Tune {
        var result = tune
        result.parts = tune.parts.map { part in
            var newPart = part
            newPart.measures = part.measures.map { measure in
                Measure(notes: measure.notes.flatMap { expand($0) }, endingNumbers: measure.endingNumbers)
            }
            return newPart
        }
        return result
    }
}
