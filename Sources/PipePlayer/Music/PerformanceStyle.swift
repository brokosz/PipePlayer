import Foundation

/// How a tune is *played*, as opposed to how it's written — the layer of
/// interpretation a piper adds on top of the notation. Applied just before
/// events are built, so it shapes both live playback and export identically
/// without touching the parsed tune itself.
///
/// Currently strathspey-only. Written strathspey rhythm is dot-cut (dotted
/// eighth + sixteenth, 3:1) and its reverse, the Scotch snap; rendered
/// literally, that reads as a lazy swing. Pipers point it: the dotted note
/// is held longer and the cut is much shorter than written.
///
/// Never by inserting silence, though — a bagpipe or practice chanter
/// can't stop sounding between notes, so all the crispness has to come
/// from the cut timing (and the gracenotes) alone. An earlier version
/// shortened each note's sounding length to detach them, and it read as
/// wrong immediately.
enum PerformanceStyle {
    /// The cut note's share of a dot-cut or cut-dot pair. Written, it's
    /// 1/4 (3:1); this sharpens it to 5:1. Pair totals are preserved, so
    /// the beat never moves — only where inside the beat the cut lands.
    static let strathspeyCutFraction = 1.0 / 6.0

    static func apply(to tune: Tune) -> Tune {
        var result = tune
        result.parts = tune.parts.map { part in
            // A part's own rhythm wins — a set can mix tune types.
            guard (part.rhythm ?? tune.rhythm) == .strathspey else { return part }
            var part = part
            part.measures = part.measures.map { measure in
                var measure = measure
                measure.notes = sharpenDotCuts(measure.notes)
                return measure
            }
            return part
        }
        return result
    }

    /// Finds adjacent 3:1 pairs (either order) within a measure and
    /// re-proportions them to `strathspeyCutFraction`. Doesn't look across
    /// barlines, and skips a pair whose first note is tied into the second
    /// (that's one sustained sound, not a dot-cut).
    private static func sharpenDotCuts(_ notes: [NoteEvent]) -> [NoteEvent] {
        var notes = notes
        var i = 0
        while i + 1 < notes.count {
            let a = notes[i]
            let b = notes[i + 1]
            let da = effectiveDuration(a)
            let db = effectiveDuration(b)
            let isDotCutPair = !a.isRest && !b.isRest && !a.isTiedToNext
                && (abs(da - 3 * db) < 0.0001 || abs(db - 3 * da) < 0.0001)
            guard isDotCutPair else {
                i += 1
                continue
            }
            let total = da + db
            let cut = total * strathspeyCutFraction
            let firstIsLong = da > db
            notes[i].duration = firstIsLong ? total - cut : cut
            notes[i + 1].duration = firstIsLong ? cut : total - cut
            notes[i].isDotted = false
            notes[i + 1].isDotted = false
            i += 2
        }
        return notes
    }

    private static func effectiveDuration(_ note: NoteEvent) -> Double {
        note.duration * (note.isDotted ? 1.5 : 1.0)
    }
}
