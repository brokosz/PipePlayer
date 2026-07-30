import Foundation

enum MusicXMLParserError: Error, LocalizedError {
    case invalidXML
    case noPartFound

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "This doesn't look like a valid MusicXML file."
        case .noPartFound:
            return "No playable part was found in this MusicXML file."
        }
    }
}

/// Parses MusicXML (`.musicxml`/`.xml`, and `.mxl` via `MXLArchiveReader`)
/// into one `Voice` per `<part>` element, via Foundation's built-in
/// `XMLParser` (SAX-style) — no third-party XML library needed.
///
/// Every `<part>` is read (confirmed necessary against a real file, "Hard
/// Times Come Again No More", which uses three parts — "melody", "harm1",
/// "harm2" — as a genuine harmony arrangement meant to sound *together*, not
/// as sequential tune sections or an unplayed drone staff). Each part
/// accumulates its own measures/parts independently via a `PartAccumulator`;
/// score-level facts (title, composer, tempo, time signature) are shared
/// across all voices since they describe one piece. `<chord/>`-tagged notes
/// are still skipped — that's MusicXML's *own* mechanism for stacking extra
/// pitches on a single note within one part/staff, a different thing from
/// multiple `<part>` elements.
///
/// Grace notes (`<grace/>`) are literal pitches in MusicXML — unlike BWW's
/// named ornament tokens, there's no lookup table involved. They're
/// inserted directly as short `NoteEvent`s, the same approach `ABCParser`
/// uses for its `{...}` grace groups.
///
/// Repeat/ending structure (confirmed against a real MusicXML test file,
/// `w3c-cg/musicxml`'s `repeats-jumps.musicxml`): a `<barline location="left">`
/// with `<repeat direction="forward"/>` starts a new repeatable section;
/// `<barline location="right">` with `<repeat direction="backward"/>` ends
/// one — these can appear in either order relative to each other (a backward
/// repeat with no preceding forward one means "repeat from the start"),
/// which this parser's flush-on-boundary state machine handles naturally
/// without needing to special-case that. An explicit `times="N"` repeat
/// count beyond 2 isn't modeled — `TunePart.hasRepeat` is a simple boolean,
/// matching how bagpipe tunes are virtually always structured (AABB, not
/// three-or-more-times repeats).
final class MusicXMLParser: NSObject, XMLParserDelegate {

    /// Backward-compatible single-voice entry point — returns just the first
    /// `<part>`'s tune. Prefer `parseVoices(_:)` for anything that should
    /// respect multiple simultaneous voices/harmonies.
    static func parse(_ data: Data) throws -> Tune {
        guard let first = try parseVoices(data).first else {
            throw MusicXMLParserError.noPartFound
        }
        return first.tune
    }

    static func parseVoices(_ data: Data) throws -> [Voice] {
        let parser = MusicXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw parser.parseError ?? MusicXMLParserError.invalidXML
        }
        return try parser.buildVoices()
    }

    // MARK: - Per-part accumulated state

    /// Holds everything that must persist across a single `<part>`'s worth
    /// of parsing without leaking into another part's results. Transient
    /// "note currently being built" scratch state stays on the parser
    /// itself (see below) since only one `<note>` is ever open at a time
    /// regardless of which part it belongs to.
    private final class PartAccumulator {
        let id: String
        var name: String
        var parts: [TunePart] = []
        var currentMeasures: [Measure] = []
        var currentNotes: [NoteEvent] = []
        var activeEndingNumbers: Set<Int> = []
        var endingNumbersToRemoveAtMeasureEnd: Set<Int> = []
        var partHasRepeat = false
        var shouldFlushPartAtMeasureEnd = false
        var divisions: Double = 1
        // Last resolved (non-rest) melodic pitch in this part, used to
        // disambiguate G/A's low/high octave by melodic contour — see
        // `Pitch.nearest(toMIDINumber:previous:)`.
        var lastResolvedPitch: Pitch?

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        func flushMeasure() {
            if !currentNotes.isEmpty {
                currentMeasures.append(Measure(notes: currentNotes, endingNumbers: Array(activeEndingNumbers).sorted()))
                currentNotes.removeAll()
            }
            activeEndingNumbers.subtract(endingNumbersToRemoveAtMeasureEnd)
            endingNumbersToRemoveAtMeasureEnd.removeAll()
        }

        func flushPart() {
            flushMeasure()
            if !currentMeasures.isEmpty {
                parts.append(TunePart(measures: currentMeasures, hasRepeat: partHasRepeat))
                currentMeasures.removeAll()
            }
            partHasRepeat = false
        }
    }

    // MARK: - Accumulated score-level state (shared across all voices)

    private var parseError: Error?
    private var workTitle: String?
    private var movementTitle: String?
    private var composer: String?
    private var timeSignature = "2/4"
    private var tempo: Double?

    // Fallback tempo source: a visual metronome mark, used only when no
    // <sound tempo> is ever found — confirmed necessary against a real file
    // that had a <metronome> mark (quarter = 76) but zero <sound tempo>
    // elements anywhere, so relying on <sound tempo> alone silently dropped
    // to the 90 default and played noticeably faster than intended.
    private var metronomePerMinute: Double?
    private var metronomeBeatUnit: String?
    private var metronomeBeatUnitDotCount = 0
    private var isInsideMetronome = false

    // MARK: - Part bookkeeping

    private var isInsidePartList = false
    private var currentScorePartIDForName: String?
    private var partNames: [String: String] = [:]
    private var accumulators: [String: PartAccumulator] = [:]
    private var partOrder: [String] = []
    private var currentPartID: String?

    private var current: PartAccumulator? {
        guard let currentPartID else { return nil }
        return accumulators[currentPartID]
    }

    // Per-<barline> scratch state, resolved at </barline>. Only one barline
    // is ever "in progress" at a time (same reasoning as note scratch state).
    private var barlineLocation: String?
    private var barlineStyle: String?
    private var barlineHasForwardRepeat = false
    private var barlineHasBackwardRepeat = false
    private var barlineHasJumpMarker = false

    // MARK: - Per-<note> scratch state

    private var noteStep: String?
    private var noteOctave: Int?
    private var noteAlter = 0
    private var noteDurationTicks: Double?
    private var noteType: String?
    private var noteDotCount = 0
    private var noteIsRest = false
    private var noteIsGrace = false
    private var noteIsChord = false
    private var noteIsTieStart = false
    // <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
    // for tuplets (e.g. a triplet eighth: <type>eighth</type> but sounds for
    // only 2/3 of a written eighth's duration, not the full written value).
    private var noteTupletActualNotes: Int?
    private var noteTupletNormalNotes: Int?

    private var textBuffer = ""
    private var isInsideCreatorComposer = false

    /// A part boundary isn't only an explicit `<repeat>` — any structurally
    /// significant barline should split the part into a new section for
    /// progress-tracking purposes: a double bar (`light-light`/`light-heavy`/
    /// `heavy-light`/`heavy-heavy`), a coda/segno marker, or (via the
    /// `<sound>` handler below) a D.C./D.S./To Coda/Fine jump.
    ///
    /// A bare style change (no repeat/coda/segno backing it) is only trusted
    /// on the "right" side — a measure that has actually just concluded.
    /// "Left" needs a real repeat/coda/segno to count. Confirmed necessary
    /// against a real file where a plain pickup measure's trailing barline
    /// was tagged `location="left"` with a `heavy-light` style (a common
    /// exporter quirk: the boundary *between* two measures tagged on the
    /// earlier one's trailing edge rather than the later one's leading
    /// edge) — trusting bare "left" styles isolated the pickup as its own
    /// spurious one-measure "part" instead of recognizing there was no
    /// genuine internal section break at all.
    private func applyBarlineIfStructural() {
        defer {
            barlineLocation = nil
            barlineStyle = nil
            barlineHasForwardRepeat = false
            barlineHasBackwardRepeat = false
            barlineHasJumpMarker = false
        }
        guard let current else { return }

        let structuralStyles: Set<String> = ["light-light", "light-heavy", "heavy-light", "heavy-heavy"]
        let isStructuralStyle = barlineStyle.map { structuralStyles.contains($0) } ?? false
        let hasUnambiguousSignal = barlineHasForwardRepeat || barlineHasBackwardRepeat || barlineHasJumpMarker
        let isStructural = hasUnambiguousSignal || (isStructuralStyle && barlineLocation != "left")
        guard isStructural else { return }

        if barlineHasBackwardRepeat {
            current.partHasRepeat = true
        }

        if barlineLocation == "left" {
            current.flushPart() // this measure hasn't accumulated any notes yet — safe to flush now
        } else {
            current.shouldFlushPartAtMeasureEnd = true // defer until this measure's notes are captured
        }
    }

    private func buildVoices() throws -> [Voice] {
        let title = workTitle ?? movementTitle ?? "Untitled"
        let resolvedTempo = tempo ?? metronomeQuarterBPM() ?? 90

        var voices: [Voice] = []
        for id in partOrder {
            guard let acc = accumulators[id] else { continue }
            acc.flushPart()
            guard !acc.parts.isEmpty else { continue }
            let tune = Tune(title: title, composer: composer, tempo: resolvedTempo, timeSignature: timeSignature, parts: acc.parts)
            voices.append(Voice(id: id, name: acc.name, tune: tune))
        }
        guard !voices.isEmpty else { throw MusicXMLParserError.noPartFound }
        return voices
    }

    /// Converts a `<metronome><beat-unit>X</beat-unit><per-minute>Y</per-minute>`
    /// mark to quarter-note BPM — e.g. beat-unit "half" at 60/min is 120
    /// quarter notes/min (a half note takes twice as long, so twice as many
    /// quarters fit in the same minute).
    private func metronomeQuarterBPM() -> Double? {
        guard let perMinute = metronomePerMinute else { return nil }
        let unitValue = Self.noteTypeDurations[metronomeBeatUnit ?? "quarter"] ?? 1.0
        let dotMultiplier = 1.0 + (metronomeBeatUnitDotCount > 0 ? (1.0 - pow(0.5, Double(metronomeBeatUnitDotCount))) : 0.0)
        return perMinute * unitValue * dotMultiplier
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        switch elementName {
        case "part-list":
            isInsidePartList = true

        case "score-part":
            if isInsidePartList, let id = attributeDict["id"] {
                currentScorePartIDForName = id
            }

        case "part":
            guard let id = attributeDict["id"] else { break }
            currentPartID = id
            if accumulators[id] == nil {
                if !partOrder.contains(id) { partOrder.append(id) }
                let name = partNames[id] ?? "Voice \(partOrder.count)"
                accumulators[id] = PartAccumulator(id: id, name: name)
            }

        case "creator":
            isInsideCreatorComposer = (attributeDict["type"] == "composer")

        case "note":
            guard current != nil else { return }
            noteStep = nil
            noteOctave = nil
            noteAlter = 0
            noteDurationTicks = nil
            noteType = nil
            noteDotCount = 0
            noteIsRest = false
            noteIsGrace = false
            noteIsChord = false
            noteIsTieStart = false

        case "rest":
            guard current != nil else { return }
            noteIsRest = true

        case "grace":
            guard current != nil else { return }
            noteIsGrace = true

        case "chord":
            guard current != nil else { return }
            noteIsChord = true

        case "dot":
            guard current != nil else { return }
            noteDotCount += 1

        case "tie":
            guard current != nil else { return }
            if attributeDict["type"] == "start" { noteIsTieStart = true }

        case "sound":
            guard current != nil else { return }
            if let tempoString = attributeDict["tempo"], let value = Double(tempoString) {
                tempo = value
            }
            // D.C./D.S./To Coda/Fine — jump/section-end instructions that
            // aren't tied to a specific barline's left/right side, so (like
            // a forward repeat) it's safe to flush as soon as they're seen.
            let jumpAttributes = ["dacapo", "dalsegno", "tocoda", "fine", "segno", "coda"]
            if jumpAttributes.contains(where: { attributeDict[$0] != nil }) {
                current?.flushPart()
            }

        case "metronome":
            guard current != nil else { return }
            isInsideMetronome = true

        case "beat-unit-dot":
            guard current != nil, isInsideMetronome else { return }
            metronomeBeatUnitDotCount += 1

        case "barline":
            guard current != nil else { return }
            barlineLocation = attributeDict["location"] ?? "right" // schema default
            barlineStyle = nil
            barlineHasForwardRepeat = false
            barlineHasBackwardRepeat = false
            barlineHasJumpMarker = false

        case "repeat":
            guard current != nil else { return }
            if attributeDict["direction"] == "forward" { barlineHasForwardRepeat = true }
            else if attributeDict["direction"] == "backward" { barlineHasBackwardRepeat = true }

        case "coda", "segno":
            guard current != nil else { return }
            barlineHasJumpMarker = true

        case "ending":
            guard let current else { return }
            if let numbersString = attributeDict["number"] {
                let numbers = numbersString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if attributeDict["type"] == "start" {
                    current.activeEndingNumbers.formUnion(numbers)
                } else {
                    // "stop"/"discontinue" — this measure (whose right
                    // barline this is) still belongs to the ending, so
                    // defer actually removing it until after this measure
                    // is flushed (see flushMeasure).
                    current.endingNumbersToRemoveAtMeasureEnd.formUnion(numbers)
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        textBuffer = ""

        switch elementName {
        case "part-list":
            isInsidePartList = false

        case "score-part":
            currentScorePartIDForName = nil

        case "part-name":
            if let id = currentScorePartIDForName, !text.isEmpty {
                partNames[id] = text
            }

        case "part":
            currentPartID = nil

        case "work-title":
            if workTitle == nil, !text.isEmpty { workTitle = text }

        case "movement-title":
            if movementTitle == nil, !text.isEmpty { movementTitle = text }

        case "creator":
            if isInsideCreatorComposer, !text.isEmpty { composer = text }
            isInsideCreatorComposer = false

        case "beat-unit":
            guard isInsideMetronome, metronomeBeatUnit == nil else { break }
            metronomeBeatUnit = text

        case "per-minute":
            guard isInsideMetronome, metronomePerMinute == nil else { break }
            metronomePerMinute = Double(text)

        case "metronome":
            isInsideMetronome = false

        case "bar-style":
            guard current != nil else { break }
            barlineStyle = text

        case "barline":
            guard current != nil else { break }
            applyBarlineIfStructural()

        case "divisions":
            guard let current else { break }
            if let value = Double(text), value > 0 { current.divisions = value }

        case "beats":
            guard current != nil else { break }
            pendingBeats = text

        case "beat-type":
            guard current != nil else { break }
            if let beats = pendingBeats {
                timeSignature = "\(beats)/\(text)"
                pendingBeats = nil
            }

        case "step":
            guard current != nil else { break }
            noteStep = text

        case "octave":
            guard current != nil else { break }
            noteOctave = Int(text)

        case "alter":
            guard current != nil else { break }
            noteAlter = Int(Double(text) ?? 0)

        case "duration":
            guard current != nil else { break }
            noteDurationTicks = Double(text)

        case "type":
            guard current != nil else { break }
            noteType = text

        case "actual-notes":
            guard current != nil else { break }
            noteTupletActualNotes = Int(text)

        case "normal-notes":
            guard current != nil else { break }
            noteTupletNormalNotes = Int(text)

        case "note":
            guard current != nil else { break }
            finishNote()

        case "measure":
            guard let current else { break }
            current.flushMeasure()
            if current.shouldFlushPartAtMeasureEnd {
                current.flushPart()
                current.shouldFlushPartAtMeasureEnd = false
            }

        default:
            break
        }
    }

    private var pendingBeats: String?

    // Quarter-beat value for each standard MusicXML <type> name.
    private static let noteTypeDurations: [String: Double] = [
        "whole": 4.0, "half": 2.0, "quarter": 1.0, "eighth": 0.5,
        "16th": 0.25, "32nd": 0.125, "64th": 0.0625
    ]

    private func finishNote() {
        defer {
            noteStep = nil
            noteOctave = nil
            noteAlter = 0
            noteDurationTicks = nil
            noteType = nil
            noteDotCount = 0
            noteIsRest = false
            noteIsGrace = false
            noteIsChord = false
            noteIsTieStart = false
            noteTupletActualNotes = nil
            noteTupletNormalNotes = nil
        }

        guard let current else { return }

        // Chord notes sound together with the previous note rather than
        // sequentially — no intra-part polyphony model, so they're skipped
        // entirely rather than double-counting time or overwriting a pitch.
        // (Real polyphony across multiple *parts* is handled one level up,
        // by treating each part as its own simultaneous Voice.)
        guard !noteIsChord else { return }

        let dotMultiplier = 1.0 + (noteDotCount > 0 ? (1.0 - pow(0.5, Double(noteDotCount))) : 0.0)
        let baseDuration = self.baseDuration(divisions: current.divisions)
        // A tuplet's <type> is still the plain written note value (e.g. a
        // triplet eighth is still <type>eighth</type>) — without this, a
        // triplet eighth would play as a full eighth (1.5x too long) instead
        // of the 2/3 it actually sounds for.
        let tupletRatio: Double
        if let actual = noteTupletActualNotes, let normal = noteTupletNormalNotes, actual > 0 {
            tupletRatio = Double(normal) / Double(actual)
        } else {
            tupletRatio = 1.0
        }

        if noteIsRest {
            var note = NoteEvent(pitch: .lowA, duration: baseDuration * dotMultiplier * tupletRatio, embellishment: nil, isRest: true)
            note.isTiedToNext = false
            current.currentNotes.append(note)
            return
        }

        guard let step = noteStep, let octave = noteOctave else { return }
        let midi = Self.midiNumber(step: step, octave: octave, alter: noteAlter)
        let pitch = Pitch.nearest(toMIDINumber: midi, previous: current.lastResolvedPitch)
        current.lastResolvedPitch = pitch

        let duration: Double
        if noteIsGrace {
            // Grace notes conventionally carry no <duration> at all (they
            // borrow time rather than have their own) — matches
            // EmbellishmentExpander's graceDuration constant for consistency
            // with how BWW-sourced grace notes are timed.
            duration = 0.035
        } else {
            duration = baseDuration * dotMultiplier * tupletRatio
        }

        var note = NoteEvent(pitch: pitch, duration: duration, embellishment: nil)
        note.isTiedToNext = noteIsTieStart
        current.currentNotes.append(note)
    }

    /// Prefers `<type>` (whole/half/quarter/.../64th) over `<duration>`÷
    /// `<divisions>` — confirmed necessary against a real file where every
    /// single note, regardless of its actual written value, carried an
    /// identical `<duration>16</duration>` (an exporter bug: a 16th note and
    /// a dotted eighth — a 6:1 real ratio — both reported the same number).
    /// `<type>` is simpler and, per that evidence, more reliably populated;
    /// `<duration>`/`<divisions>` is the fallback only when `<type>` is
    /// absent, which does lose tuplet-ratio precision in that rare case.
    private func baseDuration(divisions: Double) -> Double {
        if let noteType, let typeDuration = Self.noteTypeDurations[noteType] {
            return typeDuration
        }
        return (noteDurationTicks ?? divisions) / divisions
    }

    private static func midiNumber(step: String, octave: Int, alter: Int) -> Int {
        let stepIndex: Int
        switch step.uppercased() {
        case "C": stepIndex = 0
        case "D": stepIndex = 2
        case "E": stepIndex = 4
        case "F": stepIndex = 5
        case "G": stepIndex = 7
        case "A": stepIndex = 9
        case "B": stepIndex = 11
        default: stepIndex = 0
        }
        return (octave + 1) * 12 + stepIndex + alter
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        if parseError == nil { parseError = error }
    }
}
