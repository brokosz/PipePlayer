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
    /// A MusicXML file authored for bagpipe music should already sit at or
    /// very near these exact values — this just absorbs octave/enharmonic
    /// mismatches rather than failing outright on anything slightly off.
    static func nearest(toMIDINumber midi: Int) -> Pitch {
        allCases.min(by: { abs($0.rawValue - midi) < abs($1.rawValue - midi) }) ?? .lowA
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

/// One repeated section of the tune (e.g. part A, part B). `MIDIEventBuilder`
/// unrolls play order from `hasRepeat` plus each measure's `endingNumbers`.
struct TunePart: Equatable, Codable {
    var measures: [Measure]
    var hasRepeat: Bool = false
}

struct Tune: Equatable, Codable {
    var title: String
    var composer: String?
    /// Beats per minute for a quarter note.
    var tempo: Double
    /// e.g. "2/4", "6/8", "4/4".
    var timeSignature: String
    var parts: [TunePart]

    static let empty = Tune(title: "Untitled", composer: nil, tempo: 90, timeSignature: "2/4", parts: [])
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
