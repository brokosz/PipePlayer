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

    /// A file can hold one tune or a whole set — several `X:` tunes back to
    /// back, each with its own header (`L:`, `M:`, `Q:` and all). A set is
    /// combined into one playable tune; see `combineSet`.
    static func parse(_ text: String) throws -> Tune {
        let rawLines = text.components(separatedBy: .newlines)
        guard !rawLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw ABCParserError.emptyInput
        }
        // A chunk with no K: (e.g. file-level preamble before the first X:)
        // isn't a tune — skip it rather than failing the whole file.
        let tunes = splitIntoTunes(rawLines).compactMap { try? parseSingleTune($0) }
        guard let first = tunes.first else { throw ABCParserError.missingKeyField }
        // A set often opens with a header-only "tune" — just a title like
        // "Grade III MEDLEY" and no music. It names the set rather than
        // being part of it (and its default tempo would otherwise skew the
        // whole set's tempo display).
        let musical = tunes.filter(hasMusic)
        guard musical.count > 1 || (musical.count == 1 && !hasMusic(first)) else {
            return musical.first ?? first
        }
        let setTitle = hasMusic(first) ? nil : first.title
        return combineSet(musical, title: setTitle)
    }

    private static func hasMusic(_ tune: Tune) -> Bool {
        tune.parts.contains { !$0.measures.isEmpty }
    }

    /// Splits on `X:` (the reference number every ABC tune starts with).
    /// A file with no `X:` at all is one tune.
    private static func splitIntoTunes(_ lines: [String]) -> [[String]] {
        var chunks: [[String]] = [[]]
        for line in lines {
            if line.hasPrefix("X:"), !(chunks.last?.isEmpty ?? true) {
                chunks.append([])
            }
            chunks[chunks.count - 1].append(line)
        }
        return chunks
    }

    private static func parseSingleTune(_ lines: [String]) throws -> Tune {
        var title = "Untitled"
        var composer: String?
        var timeSignature = "2/4"
        var defaultLength = 0.5 // quarter-beats per unit note length; ABC default L:1/8
        var statedTempo: StatedTempo?
        var rhythmHint: String?
        var bodyLines: [String] = []
        var sawKey = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if sawKey {
                // Field lines inside the body (`P:A` part labels, `W:`
                // lyrics, `N:` notes) aren't music — a `P:A` used to come
                // through as a stray low A. A part label is a real
                // section boundary, so it becomes one.
                if isFieldLine(trimmed) {
                    if trimmed.hasPrefix("P:") { bodyLines.append("||") }
                    continue
                }
                bodyLines.append(line)
                continue
            }
            guard isFieldLine(trimmed) else {
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
                timeSignature = normalizeMeter(value)
            case "L":
                if let parsed = parseFraction(value) { defaultLength = parsed * 4 }
            case "Q":
                statedTempo = parseTempo(value) ?? statedTempo
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

        // A bare `Q:98` — how essentially every piping ABC file states its
        // tempo (checked: all ~2,400 in a real collection) — is read at the
        // meter's own natural beat, the same convention BWW's TuneTempo
        // uses: the half note for cut time, the dotted quarter for compound
        // time. Read as plain quarter notes, a `M:C|` reel at `Q:98` played
        // at exactly half speed. (The ABC 2.1 spec's own reading of a bare
        // Q: — unit notes per minute — is clearly not what these files mean:
        // it'd put a strathspey marked 130 at 65 quarters a minute.) A tempo
        // with an explicit note value (`Q:1/4=90`) says exactly what it
        // means and is taken as given. Slow airs, laments, and songs aren't
        // counted in compound beats even when written in 6/8, so they're
        // never scaled (see `TuneRhythm.isFreeTempoGenre`).
        let rhythm = rhythmHint.flatMap(TuneRhythm.matching)
        let isFreeTempo = rhythmHint.map(TuneRhythm.isFreeTempoGenre) ?? false
        let meterScale = isFreeTempo ? 1.0 : BWWParser.tempoScaleFactor(forTimeSignature: timeSignature)
        let tempo: Double
        let scale: Double
        switch statedTempo {
        case .withUnit(let bpm, let unitInQuarters):
            tempo = bpm * unitInQuarters
            scale = unitInQuarters
        case .bare(let bpm):
            tempo = bpm * meterScale
            scale = meterScale
        case nil:
            // No Q: at all — the tune type's conventional default, stated
            // at the same natural beat (see TuneRhythm.defaultTempo).
            tempo = (rhythm?.defaultTempo ?? 90) * meterScale
            scale = meterScale
        }

        return Tune(title: title, composer: composer, tempo: tempo, timeSignature: timeSignature,
                    parts: parts, rhythm: rhythm, tempoScaleFactor: scale)
    }

    /// Plays a set's tunes back to back as one tune, each at its own
    /// tempo: the combined tune runs at the first tune's tempo, and every
    /// later tune's note durations are stretched by (first tempo ÷ its
    /// tempo) so it still sounds at its own speed. The tempo control then
    /// scales the whole set together, the way a band speeds up or slows
    /// down a medley. Each part keeps its own tune type, so a strathspey
    /// in a set is still interpreted as one.
    private static func combineSet(_ tunes: [Tune], title: String? = nil) -> Tune {
        let lead = tunes[0]
        var parts: [TunePart] = []
        for tune in tunes {
            let stretch = tune.tempo > 0 ? lead.tempo / tune.tempo : 1
            for var part in tune.parts {
                part.rhythm = tune.rhythm
                part.measures = part.measures.map { measure in
                    var measure = measure
                    measure.notes = measure.notes.map { note in
                        var note = note
                        note.duration *= stretch
                        return note
                    }
                    return measure
                }
                parts.append(part)
            }
        }
        var composers: [String] = []
        for composer in tunes.compactMap(\.composer) where !composers.contains(composer) {
            composers.append(composer)
        }
        return Tune(
            title: title ?? tunes.map(\.title).joined(separator: " / "),
            composer: composers.isEmpty ? nil : composers.joined(separator: " / "),
            tempo: lead.tempo,
            timeSignature: lead.timeSignature,
            parts: parts,
            rhythm: nil, // per part instead — see above
            tempoScaleFactor: lead.tempoScaleFactor
        )
    }

    // MARK: - Header helpers

    /// `X:`-style field line: a letter, then a colon. Excludes `A:|`-style
    /// body lines, where the colon is a repeat sign after a note.
    private static func isFieldLine(_ trimmed: String) -> Bool {
        let chars = Array(trimmed.prefix(3))
        guard chars.count >= 2, chars[0].isLetter, chars[1] == ":" else { return false }
        if chars.count == 3, chars[2] == "|" || chars[2] == ":" { return false }
        return true
    }

    /// `M:C` is common time and `M:C|` cut time; converters also sometimes
    /// glue a barline onto the meter (`M:C[|`, `M:6/8e|`). Normalized to a
    /// plain fraction so the tempo-scale rules can read it.
    private static func normalizeMeter(_ raw: String) -> String {
        let compact = raw.replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix("C|") { return "2/2" }
        if compact.hasPrefix("C") { return "4/4" }
        let fraction = compact.prefix { $0.isNumber || $0 == "/" }
        return fraction.contains("/") ? String(fraction) : raw
    }

    private static func parseFraction(_ s: String) -> Double? {
        let comps = s.split(separator: "/")
        guard comps.count == 2, let n = Double(comps[0]), let d = Double(comps[1]), d != 0 else { return nil }
        return n / d
    }

    private enum StatedTempo {
        /// `Q:98` — no note value given; read at the meter's natural beat.
        case bare(Double)
        /// `Q:3/8=120` — the beat is spelled out, as quarter notes.
        case withUnit(bpm: Double, unitInQuarters: Double)
    }

    private static func parseTempo(_ s: String) -> StatedTempo? {
        // Formats: "90", "1/4=90", "3/8=120" — plus quoted text like
        // "Allegro", which is display-only and ignored.
        let stripped = s.replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let plain = Double(stripped) { return .bare(plain) }
        let parts = stripped.split(separator: "=")
        guard parts.count == 2, let bpm = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        guard let unit = parseFraction(parts[0].trimmingCharacters(in: .whitespaces)) else { return .bare(bpm) }
        return .withUnit(bpm: bpm, unitInQuarters: unit / 0.25)
    }

    // MARK: - Body tokenizing

    private enum BodyToken: Equatable {
        case note(NoteEvent)
        case barBreak      // a plain "|"
        case partBreak     // "||", "|]", "[|", or a P: label
        case repeatStart   // "|:" (or the second half of "::")
        /// ":|" — `followedByEnding` for ":|2" / ":|[2", where the
        /// repeated part continues into its second ending rather than
        /// closing here.
        case repeatEnd(followedByEnding: Bool)
        case endingStart([Int]) // "|1", ":|2", "[1", "[2"
        case endingClose        // "]" closing a bracketed "[1 … ]" ending
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
            // Inline field (`[M:6/8]`, `[I:350]`) — skipped whole, or its
            // colon would read as a repeat sign.
            func isInlineField(at index: Int) -> Bool {
                chars[index] == "[" && index + 2 < chars.count
                    && chars[index + 1].isLetter && chars[index + 2] == ":"
            }
            if isInlineField(at: i) {
                while i < chars.count && chars[i] != "]" { i += 1 }
                i += 1
                continue
            }
            // Bar / repeat / ending markers.
            if ch == "|" || ch == ":" || ch == "[" || ch == "]" {
                var run = ""
                // Stops short of an inline field's bracket (`|[M:C|]`) so the
                // check above gets to skip it on the next pass.
                while i < chars.count && "|:[]".contains(chars[i]) && !isInlineField(at: i) {
                    run.append(chars[i])
                    i += 1
                }
                // Ending numbers follow a bar or an opening bracket directly
                // ("|1", ":|2", "[2") — never a closing one, where a digit
                // would be a chord's length instead.
                var endingNumbers: [Int] = []
                if let last = run.last, last == "|" || last == "[" {
                    var spec = ""
                    while i < chars.count, chars[i].isNumber || chars[i] == "," || chars[i] == "-" {
                        spec.append(chars[i])
                        i += 1
                    }
                    endingNumbers = parseEndingNumbers(spec)
                }
                tokens.append(contentsOf: barTokens(run: run, endingNumbers: endingNumbers))
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
                    // Grace notes borrow their time from the note they
                    // decorate (capped at half its duration) rather than
                    // adding new, un-notated time — otherwise a heavily-
                    // ornamented tune plays back audibly slower than its
                    // stated tempo purely from accumulated grace-note
                    // overhead. Matches EmbellishmentExpander's identical
                    // borrowing for BWW/BMW's named-token embellishments.
                    let totalGraceDuration = pendingGraceNotes.reduce(0.0) { $0 + $1.duration }
                    let borrowed = min(totalGraceDuration, note.duration * 0.5)
                    note.duration -= borrowed
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

    /// Classifies one contiguous run of `|`, `:`, `[`, `]` — a single run
    /// can say several things at once (`]:|[2` closes a first ending, ends
    /// the repeat, and opens the second ending), so this returns them in
    /// the order they apply.
    private static func barTokens(run: String, endingNumbers: [Int]) -> [BodyToken] {
        var tokens: [BodyToken] = []
        var rest = Substring(run)
        if rest.hasPrefix("]") {
            tokens.append(.endingClose)
            rest = rest.drop { $0 == "]" }
        }
        let endsRepeat = rest.hasPrefix(":")
        let startsRepeat = rest.hasSuffix(":")
        let isDoubleBar = rest.contains("||") || rest.contains("|]") || rest.contains("[|")
        if endsRepeat {
            tokens.append(.repeatEnd(followedByEnding: !endingNumbers.isEmpty))
        } else if isDoubleBar {
            tokens.append(.partBreak)
        }
        if startsRepeat {
            tokens.append(.repeatStart)
        }
        if !endingNumbers.isEmpty {
            tokens.append(.endingStart(endingNumbers))
        }
        if tokens.isEmpty || tokens == [.endingClose] {
            tokens.append(.barBreak)
        }
        return tokens
    }

    /// "1" → [1], "1,3" → [1, 3], "1-3" → [1, 2, 3].
    private static func parseEndingNumbers(_ spec: String) -> [Int] {
        var numbers: [Int] = []
        for piece in spec.split(separator: ",") {
            let bounds = piece.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 2, bounds[0] <= bounds[1] {
                numbers.append(contentsOf: bounds[0]...bounds[1])
            } else if let single = bounds.first {
                numbers.append(single)
            }
        }
        return numbers
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

    /// Maps ABC's repeat structure onto the same model BWW uses: a part
    /// either repeats or doesn't, and a measure inside a repeated part can
    /// be tagged first- or second-time only (`MIDIEventBuilder` skips it on
    /// the other pass). `|:` starts a new part — a pickup ahead of it
    /// becomes its own one-off part — and `:|` closes it as repeated (from
    /// the last part boundary when there's no `|:`, per ABC convention).
    ///
    /// An ending runs until it's closed (`]`), replaced by the next ending,
    /// or the part ends. The music after a second ending with no fresh `|:`
    /// stays tagged second-time, which sounds identical — it plays once, at
    /// the end of the second pass.
    private static func splitIntoParts(_ tokens: [BodyToken]) -> [TunePart] {
        var parts: [TunePart] = []
        var currentMeasures: [Measure] = []
        var currentNotes: [NoteEvent] = []
        var partHasRepeat = false
        var activeEnding: [Int] = []

        func flushMeasure() {
            if !currentNotes.isEmpty {
                currentMeasures.append(Measure(notes: currentNotes, endingNumbers: activeEnding))
                currentNotes.removeAll()
            }
        }
        func flushPart() {
            flushMeasure()
            if !currentMeasures.isEmpty {
                // Endings only mean something in a repeated part that has a
                // first ending to go with them. Otherwise, play every bar on
                // every pass rather than silently skipping "second-time"
                // bars: a part that never repeats has no second pass, and a
                // second ending with no first is a converter artifact — 22
                // real files open with a stray `:|2` before any music, and
                // an EPipes export marks a lead-in note `[2` — both of which
                // otherwise left half a part playing only once.
                let hasFirstEnding = currentMeasures.contains { $0.endingNumbers.contains(1) }
                if !partHasRepeat || !hasFirstEnding {
                    for i in currentMeasures.indices { currentMeasures[i].endingNumbers = [] }
                }
                parts.append(TunePart(measures: currentMeasures, hasRepeat: partHasRepeat))
                currentMeasures.removeAll()
            }
            partHasRepeat = false
            activeEnding = []
        }

        for token in tokens {
            switch token {
            case .note(let n):
                currentNotes.append(n)
            case .barBreak:
                flushMeasure()
            case .partBreak, .repeatStart:
                flushPart()
            case .repeatEnd(let followedByEnding):
                flushMeasure()
                partHasRepeat = true
                if !followedByEnding { flushPart() }
            case .endingStart(let numbers):
                flushMeasure()
                activeEnding = numbers
            case .endingClose:
                flushMeasure()
                activeEnding = []
            }
        }
        flushPart()

        if parts.isEmpty {
            parts = [TunePart(measures: [], hasRepeat: false)]
        }
        return parts
    }
}
