import Foundation

enum ABCParserError: Error, LocalizedError {
    case emptyInput
    case missingKeyField

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "The ABC file is empty."
        case .missingKeyField: return "No K: (key) field found — this doesn't look like a complete ABC tune."
        }
    }
}

/// Parses ABC notation as conventionally written for Great Highland Bagpipe
/// tunes, where the octave break sits at B/c: uppercase G,A,B are Low G, Low
/// A, B, and lowercase c,d,e,f,g,a are C, D, E, F, High G, High A. Pipe
/// chanter tunes have no real accidentals (the scale is fixed), so accidental
/// marks and octave-shift commas/apostrophes are tolerated but ignored rather
/// than treated as pitch changes outside the nine-note chanter range.
enum ABCParser {

    static func parse(_ text: String) throws -> Tune {
        let rawLines = text.components(separatedBy: .newlines)
        guard !rawLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw ABCParserError.emptyInput
        }

        var title = "Untitled"
        var composer: String?
        var timeSignature = "2/4"
        var defaultLength = 0.5 // quarter-beats per unit note length; ABC default L:1/8
        var explicitTempo: Double?
        var rhythmHint: String?
        var bodyLines: [String] = []
        var sawKey = false

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if sawKey {
                bodyLines.append(line)
                continue
            }
            guard trimmed.count >= 2, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == ":" else {
                // Not a recognized header field; treat remainder as body.
                bodyLines.append(line)
                continue
            }
            let field = trimmed.first!
            let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            switch field {
            case "T":
                if title == "Untitled" { title = value }
            case "C":
                composer = value
            case "M":
                timeSignature = value
            case "L":
                if let parsed = parseFraction(value) { defaultLength = parsed * 4 }
            case "Q":
                explicitTempo = parseTempo(value) ?? explicitTempo
            case "R":
                rhythmHint = value
            case "K":
                sawKey = true
            default:
                break // X:, Z:, etc. — not needed for playback
            }
        }
        guard sawKey else { throw ABCParserError.missingKeyField }

        let body = bodyLines.joined(separator: "\n")
        let notes = parseBody(body, defaultLength: defaultLength)
        let parts = splitIntoParts(notes)

        // With no explicit Q: tempo, fall back to the tune type's own
        // conventional default (from R:, e.g. "Reel") rather than a single
        // flat number for every dance type. Like BWW's TuneTempo, this
        // default is stated at the meter's own natural beat unit (e.g. 118
        // for a jig means the dotted-quarter, not the quarter note itself),
        // so it needs the same compound-meter scaling BWWParser applies to
        // an explicit TuneTempo — otherwise the same tune type would end up
        // at a different real speed depending on which format it came from.
        let rhythm = rhythmHint.flatMap(TuneRhythm.matching)
        let tempo = explicitTempo
            ?? rhythm.map { $0.defaultTempo * BWWParser.tempoScaleFactor(forTimeSignature: timeSignature) }
            ?? 90

        return Tune(title: title, composer: composer, tempo: tempo, timeSignature: timeSignature, parts: parts)
    }

    // MARK: - Header helpers

    private static func parseFraction(_ s: String) -> Double? {
        let comps = s.split(separator: "/")
        guard comps.count == 2, let n = Double(comps[0]), let d = Double(comps[1]), d != 0 else { return nil }
        return n / d
    }

    private static func parseTempo(_ s: String) -> Double? {
        // Formats: "90", "1/4=90", "3/8=120"
        if let plain = Double(s) { return plain }
        let parts = s.split(separator: "=")
        guard parts.count == 2, let bpm = Double(parts[1]) else { return nil }
        if let unit = parseFraction(String(parts[0])) {
            return bpm * (unit / 0.25)
        }
        return bpm
    }

    // MARK: - Body tokenizing

    private enum BodyToken {
        case note(NoteEvent)
        case barBreak      // "|", "|:", ":|", "::", "[|", "|]"
        case partBreak     // "||" specifically — used to split parts
    }

    private static func parseBody(_ body: String, defaultLength: Double) -> [BodyToken] {
        var tokens: [BodyToken] = []
        let chars = Array(body)
        var i = 0
        var pendingGraceNotes: [NoteEvent] = []
        var tripletCounters: [(remaining: Int, factor: Double)] = []

        func nextTripletFactor() -> Double {
            guard var current = tripletCounters.last else { return 1.0 }
            tripletCounters.removeLast()
            let factor = current.factor
            current.remaining -= 1
            if current.remaining > 0 { tripletCounters.append(current) }
            return factor
        }

        func pitch(for letter: Character) -> Pitch? {
            switch letter {
            case "G": return .lowG
            case "A": return .lowA
            case "B": return .b
            case "c": return .c
            case "d": return .d
            case "e": return .e
            case "f": return .f
            case "g": return .highG
            case "a": return .highA
            default: return nil
            }
        }

        while i < chars.count {
            let ch = chars[i]

            if ch == "%" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if ch.isWhitespace {
                i += 1
                continue
            }
            if ch == "\\" {
                i += 1
                continue
            }
            // Accidentals — ignored (fixed chanter scale), just skip.
            if ch == "^" || ch == "_" || ch == "=" {
                i += 1
                continue
            }
            // Grace note group.
            if ch == "{" {
                i += 1
                var group: [NoteEvent] = []
                while i < chars.count && chars[i] != "}" {
                    if let p = pitch(for: chars[i]) {
                        group.append(NoteEvent(pitch: p, duration: 0.0625, embellishment: nil))
                    }
                    i += 1
                }
                if i < chars.count { i += 1 } // consume '}'
                pendingGraceNotes.append(contentsOf: group)
                continue
            }
            // Triplet marker "(3" — mark the next few notes at 2/3 duration.
            if ch == "(" , i + 1 < chars.count, chars[i + 1].isNumber {
                let n = Int(String(chars[i + 1])) ?? 3
                i += 2
                tripletCounters.append((remaining: n, factor: 2.0 / Double(n == 0 ? 3 : n)))
                continue
            }
            // Bar / repeat markers.
            if ch == "|" || ch == ":" || ch == "[" || ch == "]" {
                var run = ""
                while i < chars.count && "|:[]".contains(chars[i]) {
                    run.append(chars[i])
                    i += 1
                }
                if run.contains("||") || run == "||" {
                    tokens.append(.partBreak)
                } else {
                    tokens.append(.barBreak)
                }
                continue
            }
            // Rest.
            if ch == "z" || ch == "Z" {
                i += 1
                let (mult, consumed) = parseLengthModifier(chars, from: i)
                i += consumed
                let factor = nextTripletFactor()
                tokens.append(.note(NoteEvent(pitch: .lowA, duration: defaultLength * mult * factor, embellishment: nil, isRest: true)))
                continue
            }
            // Note.
            if let p = pitch(for: ch) {
                i += 1
                // Skip octave-shift marks; out-of-range octaves aren't meaningful
                // on a 9-note chanter scale, so we clamp to the written pitch.
                while i < chars.count && (chars[i] == "'" || chars[i] == ",") { i += 1 }
                let (mult, consumed) = parseLengthModifier(chars, from: i)
                i += consumed

                var isDotted = false
                var isTied = false
                // Broken rhythm / tie look-ahead.
                if i < chars.count {
                    if chars[i] == ">" { isDotted = true; i += 1 }
                    else if chars[i] == "<" { i += 1 /* next note gets the dot; simplified as no-op for prior */ }
                    else if chars[i] == "-" { isTied = true; i += 1 }
                }

                let factor = nextTripletFactor()
                var note = NoteEvent(pitch: p, duration: defaultLength * mult * factor, embellishment: nil)
                note.isDotted = isDotted
                note.isTiedToNext = isTied

                if !pendingGraceNotes.isEmpty {
                    for g in pendingGraceNotes { tokens.append(.note(g)) }
                    pendingGraceNotes.removeAll()
                }
                tokens.append(.note(note))
                continue
            }
            // Unrecognized character — skip.
            i += 1
        }
        return tokens
    }

    /// Parses an ABC length modifier following a note/rest letter: an optional
    /// integer multiplier, an optional "/" (halve) possibly repeated or
    /// followed by a divisor integer. Returns (multiplier, charactersConsumed).
    private static func parseLengthModifier(_ chars: [Character], from start: Int) -> (Double, Int) {
        var i = start
        var numString = ""
        while i < chars.count, chars[i].isNumber {
            numString.append(chars[i])
            i += 1
        }
        var multiplier = numString.isEmpty ? 1.0 : (Double(numString) ?? 1.0)

        if i < chars.count, chars[i] == "/" {
            var slashCount = 0
            while i < chars.count, chars[i] == "/" {
                slashCount += 1
                i += 1
            }
            var denomString = ""
            while i < chars.count, chars[i].isNumber {
                denomString.append(chars[i])
                i += 1
            }
            if let denom = Double(denomString), denom != 0 {
                multiplier /= denom
            } else {
                multiplier /= pow(2.0, Double(slashCount))
            }
        }
        return (multiplier, i - start)
    }

    // MARK: - Assembly

    private static func splitIntoParts(_ tokens: [BodyToken]) -> [TunePart] {
        var parts: [TunePart] = []
        var currentMeasures: [Measure] = []
        var currentNotes: [NoteEvent] = []
        var partHasRepeat = false

        func flushMeasure() {
            if !currentNotes.isEmpty {
                currentMeasures.append(Measure(notes: currentNotes))
                currentNotes.removeAll()
            }
        }
        func flushPart() {
            flushMeasure()
            if !currentMeasures.isEmpty {
                parts.append(TunePart(measures: currentMeasures, hasRepeat: partHasRepeat))
                currentMeasures.removeAll()
            }
            partHasRepeat = false
        }

        for token in tokens {
            switch token {
            case .note(let n):
                currentNotes.append(n)
            case .barBreak:
                flushMeasure()
            case .partBreak:
                flushPart()
            }
        }
        flushPart()

        if parts.isEmpty {
            parts = [TunePart(measures: [], hasRepeat: false)]
        }
        return parts
    }
}
