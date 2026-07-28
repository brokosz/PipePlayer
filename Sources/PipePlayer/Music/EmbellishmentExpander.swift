import Foundation

/// Expands a decorated `NoteEvent` into the flat sequence of actual notes
/// (grace notes + melody note) that should be scheduled for playback/MIDI.
///
/// Grace notes "borrow" a sliver of time rather than steal it from the
/// melody note — every recognized ornament is realized as its exact grace
/// pitches (from `BWWEmbellishmentTable`, transcribed from a real BWW-
/// compatible app's own source) each held for a brief duration, followed by
/// the melody note at its full written duration. An unrecognized token gets
/// the most conservative treatment: a single High G grace note, so a tune
/// never fails to play over one obscure ornament.
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
        let perNoteDuration = gracePitches.isEmpty
            ? graceDuration
            : min(graceDuration, maxTotalGraceDuration / Double(gracePitches.count))

        func grace(_ pitch: Pitch) -> NoteEvent {
            NoteEvent(pitch: pitch, duration: perNoteDuration, embellishment: nil)
        }
        func main() -> NoteEvent {
            var n = note
            n.embellishment = nil
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
