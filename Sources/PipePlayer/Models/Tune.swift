import Foundation

/// The nine notes of the Great Highland Bagpipe chanter scale, with their
/// conventional MIDI note numbers (G4=67 through A5=81, matching the fixed
/// chanter scale of G A B C# D E F# G A used by piping notation software).
enum Pitch: Int, CaseIterable, Codable, Equatable {
    case lowG = 67
    case lowA = 69
    case b = 71
    case c = 73
    case d = 74
    case e = 76
    case f = 78
    case highG = 79
    case highA = 81

    /// Scale-step index, low G = 0 ... high A = 8. Used by the embellishment
    /// expander to reason about "the note above/below" independent of the
    /// underlying (non-uniform) semitone spacing.
    var scaleIndex: Int {
        Pitch.allCases.firstIndex(of: self) ?? 0
    }

    static func at(scaleIndex index: Int) -> Pitch {
        let clamped = max(0, min(Pitch.allCases.count - 1, index))
        return Pitch.allCases[clamped]
    }

    /// Maps an arbitrary MIDI note number (as computed from MusicXML's
    /// step/octave/alter) onto the nearest of the 9 fixed chanter pitches.
    ///
    /// Matches by pitch class (step + alter, ignoring octave) first, falling
    /// back to raw semitone distance only when nothing shares that pitch
    /// class. A real file (auto-extracted by a third-party tool, likely from
    /// audio) wrote several notes a full octave or more below the chanter's
    /// actual range — A3, D4, F#4, B3 alongside correctly-written G4/A4 — and
    /// a pure raw-distance match collapsed ALL of them onto lowG (the
    /// chanter's lowest note, so also the closest available pitch to
    /// anything written below the whole range), since 57 (A3) is numerically
    /// closer to 67 (lowG) than to 69 (lowA) despite obviously being "an A".
    /// Matching pitch class first respects that these are the same written
    /// note in the wrong octave, not different notes that happen to be low.
    ///
    /// G and A each appear twice in the chanter's scale (low and high
    /// octave), so pitch class alone doesn't resolve them. Raw semitone
    /// distance to the written MIDI number isn't reliable here either: two
    /// real files from the same source both write their "high" G/A register
    /// at an octave number that lands EXACTLY on this app's lowG/lowA MIDI
    /// values (e.g. their high G is G4=67, identical to this app's lowG
    /// constant) — there is no distance-based way to tell those apart, since
    /// the numbers are literally the same. Instead, prefer whichever octave
    /// keeps the melodic line closest to the previously resolved pitch: real
    /// chanter melodies move mostly by step or small leaps, so a G/A that
    /// follows an upper-register note (d/e/f) is almost always the high
    /// octave, and one that follows a lower-register note (lowA/b) is almost
    /// always the low octave. Confirmed against both real files: this
    /// recovers plausible smooth melodic runs where the old raw-distance
    /// tiebreak produced repeated large, un-piping-like leaps.
    static func nearest(toMIDINumber midi: Int, previous: Pitch? = nil) -> Pitch {
        let pitchClass = ((midi % 12) + 12) % 12
        let sameClass = allCases.filter { $0.rawValue % 12 == pitchClass }
        guard !sameClass.isEmpty else {
            return allCases.min(by: { abs($0.rawValue - midi) < abs($1.rawValue - midi) }) ?? .lowA
        }
        if sameClass.count > 1, let previous {
            return sameClass.min(by: { abs($0.rawValue - previous.rawValue) < abs($1.rawValue - previous.rawValue) })!
        }
        return sameClass.min(by: { abs($0.rawValue - midi) < abs($1.rawValue - midi) })!
    }
}

/// A single ornament attached to a melody note, stored as its raw (lowercased)
/// BWW/BMW token — e.g. "thrd", "brl", "tar", "dbb", "gg". `EmbellishmentExpander`
/// resolves the token to its exact grace-note pitch sequence via
/// `BWWEmbellishmentTable` (transcribed directly from a real BWW-compatible
/// app's source, not approximated), falling back to a single conservative
/// grace note for any token the table doesn't recognize.
enum Embellishment: Equatable, Codable {
    case token(String)
}

/// A single melodic event: a chanter pitch held for a duration, optionally
/// decorated with an embellishment and/or tied to the following note.
struct NoteEvent: Equatable, Codable {
    var pitch: Pitch
    /// Duration in quarter-note beats (quarter = 1.0, eighth = 0.5, ...).
    var duration: Double
    var embellishment: Embellishment?
    var isDotted: Bool = false
    var isTiedToNext: Bool = false
    /// True for a full bar of rest (BWW rests / ABC "z").
    var isRest: Bool = false
}

struct Measure: Equatable, Codable {
    var notes: [NoteEvent]
    /// 1-indexed ending numbers this measure belongs to (e.g. [1] for a
    /// first-ending measure, [2] for a second-ending measure). Empty for a
    /// measure that isn't part of any ending — played on every repeat pass.
    var endingNumbers: [Int] = []
}

/// The standard Highland-piping dance-tune types, each with its own
/// conventional default tempo — used when a source file doesn't state an
/// explicit tempo of its own (BWW's `TuneTempo` record, ABC's `Q:` field).
/// Matched case-insensitively against BWW's free-text "Y" (tune type) record
/// or ABC's "R:" (rhythm) field.
enum TuneRhythm: String, CaseIterable, Codable {
    case march, strathspey, reel, hornpipe, jig

    var defaultTempo: Double {
        switch self {
        case .march: return 82
        case .strathspey: return 118
        case .reel: return 86
        case .hornpipe: return 88
        case .jig: return 118
        }
    }

    /// `hint` is free text like BWW's "Hornpipe." or ABC's "Reel" — matched
    /// case-insensitively and tolerant of trailing punctuation or extra
    /// words (e.g. "Strathspey & Reel", a common paired dance-set marking).
    /// Strathspey is checked before reel/march so a combined "Strathspey &
    /// Reel" hint resolves to the slower, defining half of the pair.
    static func matching(_ hint: String) -> TuneRhythm? {
        let lowered = hint.lowercased()
        for rhythm in [TuneRhythm.strathspey, .hornpipe, .march, .jig, .reel] {
            if lowered.contains(rhythm.rawValue) { return rhythm }
        }
        return nil
    }

    /// Slow airs, laments, and songs are conventionally written in whatever
    /// time signature groups their notes most legibly — often a compound one
    /// like 6/8 — but, unlike a jig or slip jig, aren't danced to a dotted-
    /// quarter pulse at all: they're free, rubato pieces where the stated
    /// tempo means the plain written beat, full stop. Standard compound-time
    /// notation (see e.g. mymusictheory.com's compound-time-signatures page)
    /// says a 6/8 tempo mark means the dotted quarter — true for a real jig
    /// (confirmed against "Biddy From Sligo": TuneTempo,132 plays at
    /// quarter-equivalent 198) — but applying that same rule to a 6/8 air
    /// inflates its tempo by 50% or more for a piece that was never counted
    /// in dotted-quarter beats to begin with. Checked before computing a
    /// compound-meter scale factor from the time signature, so this genre
    /// carve-out overrides what the meter alone would otherwise imply.
    static func isFreeTempoGenre(_ hint: String) -> Bool {
        let lowered = hint.lowercased()
        return ["air", "lament", "song"].contains { lowered.contains($0) }
    }
}

/// One repeated section of the tune (e.g. part A, part B). `MIDIEventBuilder`
/// unrolls play order from `hasRepeat` plus each measure's `endingNumbers`.
struct TunePart: Equatable, Codable {
    var measures: [Measure]
    var hasRepeat: Bool = false
    /// Overrides `Tune.rhythm` for this part — set when one file holds a
    /// whole set (an ABC file with several `X:` tunes), so a strathspey
    /// followed by a reel gets interpreted as each, not as one or the other.
    var rhythm: TuneRhythm? = nil
}

struct Tune: Equatable, Codable {
    var title: String
    var composer: String?
    /// Beats per minute for a quarter note.
    var tempo: Double
    /// e.g. "2/4", "6/8", "4/4".
    var timeSignature: String
    var parts: [TunePart]
    /// The dance type, when the source file says (BWW's "Y" record, ABC's
    /// `R:`) — drives both the default tempo at parse time and how the
    /// tune is interpreted at playback (`PerformanceStyle`).
    var rhythm: TuneRhythm? = nil
    /// What the parser multiplied the file's stated tempo by to get `tempo`
    /// in quarter notes per minute — 2 for a cut-time reel stated at the
    /// half note, 1.5 for a jig stated at the dotted quarter, 1 for most
    /// else. Recorded by the parser rather than re-derived from the meter
    /// downstream, since only the parser knows when it *didn't* scale (a
    /// slow air in 6/8 is stated at the plain beat).
    var tempoScaleFactor: Double = 1.0

    static let empty = Tune(title: "Untitled", composer: nil, tempo: 90, timeSignature: "2/4", parts: [])

    /// Every ending fix-up parsers apply, in order.
    func normalizingEndings() -> Tune {
        attachingTrailingEndings().droppingUnpairedEndings()
    }

    /// A second ending with no first ending anywhere in its part isn't an
    /// alternative to anything — real files use a lone `'22` as a stray
    /// marker (seen in old BMW exports: one on the second half of a part
    /// that's plainly played in full both times). Honoured literally, it
    /// drops half the part from one pass, so it's ignored instead.
    func droppingUnpairedEndings() -> Tune {
        var result = self
        result.parts = parts.map { part in
            guard !part.measures.contains(where: { $0.endingNumbers.contains(1) }) else { return part }
            var part = part
            part.measures = part.measures.map { measure in
                var measure = measure
                measure.endingNumbers = []
                return measure
            }
            return part
        }
        return result
    }

    /// Folds a repeat's later endings back into the part they belong to.
    ///
    /// Notation writes a second ending *after* the repeat sign (`''!I '2`
    /// in BWW, a backward repeat then `<ending number="2">` in MusicXML), so
    /// a parser that closes the part at the repeat sign leaves the second
    /// ending stranded as a little part of its own. That was wrong twice
    /// over: the progress bar showed a part the file never has, and
    /// playback dropped the ending entirely (an ending-2 measure only plays
    /// on a second pass, and the stranded part had no repeat).
    ///
    /// A part with a first ending counts too, even with no repeat sign
    /// closing it (a first ending closed by a plain part-end barline):
    /// the second ending arriving is what says it repeats.
    func attachingTrailingEndings() -> Tune {
        var merged: [TunePart] = []
        for part in parts {
            guard var previous = merged.last,
                  previous.hasRepeat || previous.measures.contains(where: { $0.endingNumbers.contains(1) })
            else {
                merged.append(part)
                continue
            }
            let trailing = part.measures.prefix { measure in
                !measure.endingNumbers.isEmpty && !measure.endingNumbers.contains(1)
            }
            guard !trailing.isEmpty else {
                merged.append(part)
                continue
            }
            previous.measures.append(contentsOf: trailing)
            previous.hasRepeat = true
            merged[merged.count - 1] = previous
            var rest = part
            rest.measures.removeFirst(trailing.count)
            if !rest.measures.isEmpty { merged.append(rest) }
        }
        var result = self
        result.parts = merged
        return result
    }
}

/// One simultaneous melodic line. ABC and BWW/BMW are inherently monophonic
/// and always produce exactly one voice ("Melody"). A MusicXML file can carry
/// several `<part>` elements representing a real harmony arrangement — e.g.
/// "melody"/"harm1"/"harm2" bridged staves meant to sound together, not
/// sequential tune sections — and each becomes its own `Voice` here, mutable
/// independently in the UI.
struct Voice: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var tune: Tune
    /// `tune.tempo` ÷ this factor is the number a player actually wrote/
    /// expects to see (e.g. 132 for a jig marked at the dotted-quarter, even
    /// though `tune.tempo` holds the quarter-note-equivalent 198 actually
    /// used for playback). BWW/BMW states tempo at the meter's own natural
    /// beat unit (quarter for simple time, half note for cut time, dotted
    /// quarter for compound time) and already bakes the scaling into
    /// `tune.tempo` at parse time — this factor is what undoes it for
    /// display. MusicXML's `<sound tempo>` is always flat quarter-note bpm
    /// by spec regardless of written meter, so MusicXML/ABC voices leave
    /// this at the default 1.0 (no scaling either way).
    var displayTempoScaleFactor: Double = 1.0
}
