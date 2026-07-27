import Foundation

enum BWWParserError: Error, LocalizedError {
    case emptyInput
    case unrecognizedHeader
    case legacyBinaryFormat

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The file is empty."
        case .unrecognizedHeader:
            return "This doesn't look like a Bagpipe Music Writer tune-code file."
        case .legacyBinaryFormat:
            return "This looks like a pre-Gold BMW-DOS binary file, which isn't supported. Only the modern BWW/BMW text tune-code format (as written by Bagpipe Music Writer Gold / Bagpipe Musicworks Gold / Bagpipe Reader) is supported."
        }
    }
}

/// Parses the shared plain-text "tune code" grammar used by both `.bww` and
/// modern (Gold-era) `.bmw` files. Pitch letters and duration suffixes are
/// verified against the real lexical rules in the `bww2tex` converter's
/// `expressions.l`; embellishment token spelling and grace-note content come
/// from `BWWEmbellishmentTable` (ground truth transcribed from a real
/// BWW-compatible app's source). Barline/repeat, dot-marker, and tie token
/// semantics are cross-checked against [tomvodi/limepipes-plugin-bww]
/// (github.com/tomvodi/limepipes-plugin-bww), a real working open-source Go
/// parser for this exact format — see the specific call-outs below for what
/// each of those corrected. An unrecognized ornament token is still
/// tokenized and attached to its note (so a tune never fails to load over one
/// obscure ornament) but `EmbellishmentExpander` renders it as a single
/// conservative grace note rather than a fully authoritative figure.
///
/// Real BWW source glues two things onto pitch/duration tokens with no
/// separator that a naive whitespace tokenizer would miss: a duration suffix
/// (`_8`, `_16`, ...) always follows immediately, and pitch letters can also
/// carry a trailing `r`/`l` — a print-layout "which side of the beam" marker
/// with no musical meaning, confirmed cosmetic against limepipes-plugin-bww's
/// `symbolmapper/melody_notes.go` (`Dr_16`/`Dl_16` map to the identical
/// symbol) — which `classifyMusicalWord` strips before matching.
enum BWWParser {

    static func parse(_ text: String) throws -> Tune {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BWWParserError.emptyInput }

        if looksLikeLegacyBinary(text) { throw BWWParserError.legacyBinaryFormat }

        let knownHeaders = [
            "Bagpipe Music Writer Gold:",
            "Bagpipe Musicworks Gold:",
            "Bagpipe Reader:"
        ]
        let hasKnownCommentHeader = knownHeaders.contains(where: { trimmed.hasPrefix($0) })
        // Older/plainer BMW exports (seen in real files from bagpipetunes.com's
        // BMW archive) skip the "Bagpipe ...:X.X" comment line entirely and
        // open directly with bare quoted strings (title/type/composer, no
        // "(T,...)" tuple) before the tune body. Since there's no fixed
        // marker to key off, fall back to a content sniff: starts with a
        // quoted string and contains both structural markers (`&` for the
        // key/stave line, `!` for bars) that every real variant uses.
        let looksLikePlainTuneCode = trimmed.hasPrefix("\"") && text.contains("&") && text.contains("!")
        guard hasKnownCommentHeader || looksLikePlainTuneCode else {
            throw BWWParserError.unrecognizedHeader
        }

        var title = "Untitled"
        var composer: String?
        var timeSignature = "2/4"
        var explicitTempo: Double?

        let tokens = tokenize(text)
        var pendingEmbellishment: Embellishment?
        var pendingEndingNumber: Int?
        var pendingTieStart = false

        var parts: [TunePart] = []
        var currentMeasures: [Measure] = []
        var currentNotes: [NoteEvent] = []
        var currentMeasureEndingNumbers: Set<Int> = []
        var partHasRepeat = false
        // A repeat can span multiple `&` systems/lines before it actually
        // closes (confirmed against limepipes-plugin-bww's barline handling
        // and a real reference tune) — an interior system-end (`!t`/`!I`)
        // must NOT flush the part while a repeat is still open; only the
        // matching `''!I` close does.
        var repeatIsOpen = false

        func flushMeasure() {
            if !currentNotes.isEmpty {
                currentMeasures.append(Measure(notes: currentNotes, endingNumbers: Array(currentMeasureEndingNumbers).sorted()))
                currentNotes.removeAll()
                currentMeasureEndingNumbers.removeAll()
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
            case .comment:
                continue

            case .titledText(let kind, let value):
                switch kind {
                case "T": if title == "Untitled" { title = value }
                case "M": composer = value
                default: break // "Y" tune type, or plain annotation text — not needed for playback
                }

            case .meterFraction(let raw):
                timeSignature = raw.replacingOccurrences(of: "_", with: "/")

            case .tempo(let bpm):
                explicitTempo = bpm

            case .signature:
                continue // key signature markers — the fixed chanter scale already bakes these in

            case .pitch(let pitch, let duration):
                var note = NoteEvent(pitch: pitch, duration: duration ?? (currentNotes.last?.duration ?? 0.5))
                if let emb = pendingEmbellishment {
                    note.embellishment = emb
                    pendingEmbellishment = nil
                }
                if let ending = pendingEndingNumber {
                    // Stays "sticky" across notes until an explicit .endEnding
                    // token — an ending typically spans a whole measure, not
                    // just the note immediately after the '1/'2 marker.
                    currentMeasureEndingNumbers.insert(ending)
                }
                if pendingTieStart {
                    // "^ts" precedes the entire note event it starts
                    // (including any embellishment prefix already consumed
                    // above), so it's this note — the first one that follows
                    // it — that gets tagged as tied onward.
                    note.isTiedToNext = true
                    pendingTieStart = false
                }
                currentNotes.append(note)

            case .rest(let duration):
                currentNotes.append(NoteEvent(pitch: .lowA, duration: duration, embellishment: nil, isRest: true))

            case .dotMarker(let count):
                // A dot token follows the note it modifies, ×1.5 for one dot
                // or ×1.75 for two — the actual mechanism for dotted rhythms
                // (not a tied pair, an earlier misreading of the format).
                // Falls back to the last already-flushed measure for the
                // rare case a dot token itself lands right at a bar boundary.
                let multiplier = count == 2 ? 1.75 : 1.5
                if !currentNotes.isEmpty {
                    currentNotes[currentNotes.count - 1].duration *= multiplier
                } else if var lastMeasure = currentMeasures.last, !lastMeasure.notes.isEmpty {
                    lastMeasure.notes[lastMeasure.notes.count - 1].duration *= multiplier
                    currentMeasures[currentMeasures.count - 1] = lastMeasure
                }

            case .tieStart:
                pendingTieStart = true

            case .tieEnd:
                // Follows the note that resolves the tie, which by this
                // point has already been appended as a normal note — nothing
                // further to do; the tied-FROM note was already marked when
                // .tieStart's flag was consumed.
                continue

            case .embellishment(let emb):
                pendingEmbellishment = emb

            case .bar:
                flushMeasure()

            case .repeatOpen:
                partHasRepeat = true
                repeatIsOpen = true

            case .repeatClose:
                repeatIsOpen = false
                flushPart()

            case .systemEnd:
                // A system/staff can end without its repeat (if any) having
                // closed yet — a repeat routinely spans multiple `&` systems
                // before the matching `''!I` actually closes it (confirmed
                // against a real reference tune), so only flush the part here
                // when no repeat is currently left open.
                flushMeasure()
                if !repeatIsOpen {
                    flushPart()
                }

            case .startEnding(let n):
                pendingEndingNumber = n

            case .endEnding:
                pendingEndingNumber = nil

            case .unknown:
                continue
            }
        }
        flushPart()

        if parts.isEmpty {
            parts = [TunePart(measures: [], hasRepeat: false)]
        }

        // No meter-based tempo reinterpretation: cross-checked against
        // tomvodi/limepipes-plugin-bww (a real BWW parser), whose tunetempo
        // test fixture shows TuneTempo passed straight through as a flat
        // integer with no cut-time doubling/halving anywhere in its
        // pipeline. An explicit TuneTempo is therefore used exactly as
        // written, for every meter — that "cut time" tempo scaling this file
        // briefly had was chasing a problem that doesn't exist at the
        // parsing level. The default when no tempo is given at all is the
        // same flat value for every tune regardless of meter; PipePlayer's
        // own tempo control is the intended way to dial in a livelier feel
        // for a specific reel, not a guessed-at per-genre default here.
        let tempo = explicitTempo ?? 90

        return Tune(title: title, composer: composer, tempo: tempo, timeSignature: timeSignature, parts: parts)
    }

    /// A `.bmw` file that doesn't start with a recognizable text header (one
    /// of the known "Bagpipe ...:" comment lines) and contains non-printable
    /// bytes early on is very likely a pre-Gold BMW-DOS binary file rather
    /// than the Gold-era text tune code — those aren't reverse-engineered
    /// reliably enough to support here.
    private static func looksLikeLegacyBinary(_ text: String) -> Bool {
        let prefix = text.prefix(64)
        let controlCharCount = prefix.unicodeScalars.filter { $0.value < 9 || ($0.value > 13 && $0.value < 32) }.count
        return controlCharCount > 2
    }

    // MARK: - Tokenizing

    private enum Token {
        case comment
        case titledText(kind: String, value: String) // T=title, M=composer, Y=tune type
        case meterFraction(String)
        case tempo(Double)
        case signature
        case pitch(Pitch, duration: Double?)
        case rest(duration: Double)
        /// `'<pitch>` (one dot, ×1.5) / `''<pitch>` (two dots, ×1.75) — the
        /// actual dotted-rhythm mechanism, applied to the *previous* note.
        case dotMarker(count: Int)
        /// `^ts`/`^te`, generic (no pitch suffix) — `^ts` precedes the note
        /// that starts a tie, `^te` follows the note that resolves it.
        case tieStart
        case tieEnd
        case embellishment(Embellishment)
        case bar
        /// `I!''` — heavy barline + repeat start.
        case repeatOpen
        /// `''!I` — heavy barline + repeat end.
        case repeatClose
        /// `!I` or `!t` — end of a system/staff line, with no repeat
        /// implied either way (a repeat, if any, may still be open and
        /// continue into the next system).
        case systemEnd
        case startEnding(Int)
        case endEnding
        case unknown(String)
    }

    // Confirmed against ~1,500 real .bmw files: only these five duration
    // codes exist — no whole-note (_1) or 64th-note (_64) code. Dotted
    // rhythms use a separate dot-marker token after the note (see
    // `.dotMarker` below), not a distinct duration code of their own.
    private static let durations: [String: Double] = [
        "_2": 2.0, "_4": 1.0, "_8": 0.5, "_16": 0.25, "_32": 0.125
    ]

    /// Scans the raw text char-by-char so quoted strings (tune title,
    /// composer, tune type, font names — all of which routinely contain
    /// spaces, e.g. `"Scotland the Brave",(T,L,10,10,Times New Roman,14,0)`)
    /// are captured whole *before* whitespace-splitting the rest into the
    /// space-delimited musical/structural words the BWW grammar otherwise uses.
    ///
    /// Older/plainer BMW exports have no "(T,...)" type tuple at all — just
    /// bare quoted strings in positional order (title, tune type, composer,
    /// ...) before the tune body starts. Those get assigned positionally,
    /// but only while still in the header (before the first `&`/`!`
    /// structural marker), so a lyric or annotation quoted later in the tune
    /// body is never mistaken for header metadata.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var plainWordBuffer = ""
        var sawStructuralMarker = false
        var bareHeaderQuoteCount = 0

        func flushWord() {
            guard !plainWordBuffer.isEmpty else { return }
            if plainWordBuffer == "&" || plainWordBuffer.contains("!") {
                sawStructuralMarker = true
            }
            tokens.append(contentsOf: classify(plainWordBuffer))
            plainWordBuffer = ""
        }

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace {
                flushWord()
                i += 1
                continue
            }
            if ch == "\"" {
                flushWord()
                var j = i + 1
                var quoted = ""
                while j < chars.count && chars[j] != "\"" {
                    quoted.append(chars[j])
                    j += 1
                }
                j += 1 // consume closing quote
                var kindChar: String?
                if j < chars.count, chars[j] == ",", j + 1 < chars.count, chars[j + 1] == "(" {
                    kindChar = String(chars[j + 2])
                    // Skip to the matching closing paren of the tuple.
                    var depth = 1
                    j += 2
                    while j < chars.count && depth > 0 {
                        if chars[j] == "(" { depth += 1 }
                        if chars[j] == ")" { depth -= 1 }
                        j += 1
                    }
                } else if j < chars.count, chars[j] == "," {
                    // Plain quoted annotation with no type tuple — ignorable.
                    j += 1
                } else if !sawStructuralMarker {
                    // Bare header quote, no tuple, no trailing comma at all —
                    // the older positional style: 1st = title, 2nd = tune
                    // type (ignored downstream), 3rd = composer, rest ignored.
                    let positionalKind = ["T", "Y", "M"]
                    if bareHeaderQuoteCount < positionalKind.count {
                        kindChar = positionalKind[bareHeaderQuoteCount]
                    }
                    bareHeaderQuoteCount += 1
                }
                if let kind = kindChar {
                    tokens.append(.titledText(kind: kind, value: quoted))
                }
                i = j
                continue
            }
            plainWordBuffer.append(ch)
            i += 1
        }
        flushWord()
        return tokens
    }

    private static func isMeterFraction(_ word: String) -> Bool {
        let comps = word.split(separator: "_")
        return comps.count == 2 && comps.allSatisfy { Int($0) != nil }
    }

    private static func classify(_ word: String) -> [Token] {
        if word.hasPrefix("Bagpipe") {
            return [.comment]
        }
        if isMeterFraction(word) {
            return [.meterFraction(word)]
        }
        // Bare "C" (common time) and "C_"/"c_" (cut time / alla breve) are
        // valid non-numeric time signature tokens alongside "2_4"-style
        // fractions — reused as synthetic fraction strings so the same
        // .meterFraction handling below produces the right timeSignature.
        if word == "C" {
            return [.meterFraction("4_4")]
        }
        if word == "C_" || word == "c_" {
            return [.meterFraction("2_2")]
        }
        if word.hasPrefix("TuneTempo,") {
            // Real format is "TuneTempo,90" — plain digits after the comma,
            // no parens (unlike the "Name,(...)" metadata blocks above it).
            let digits = word.dropFirst("TuneTempo,".count).filter(\.isNumber)
            return Double(digits).map { [.tempo($0)] } ?? []
        }
        if word == "sharpf" || word == "sharpc" {
            return [.signature]
        }
        // Barline/repeat tokens — exact matches only (not substring
        // "contains" checks): "I!" (heavy barline, no repeat, no system-end)
        // is deliberately treated the same as a plain "!" below, since it
        // doesn't affect playback; "!I" and "!t" both end a system without
        // implying anything about a repeat one way or the other; only
        // "I!''"/"''!I" actually open/close a repeat.
        if word == "!" || word == "I!" {
            return [.bar]
        }
        if word == "I!''" {
            return [.repeatOpen]
        }
        if word == "''!I" {
            return [.repeatClose]
        }
        if word == "!I" || word == "!t" {
            return [.systemEnd]
        }
        if word == "'1" || word == "'2" {
            return Int(word.dropFirst()).map { [.startEnding($0)] } ?? []
        }
        if word == "_'" || word == "bis_'" {
            return [.endEnding]
        }
        if word == "^ts" {
            return [.tieStart]
        }
        if word == "^te" {
            return [.tieEnd]
        }
        // Dot marker: `'<pitch>` (one dot) / `''<pitch>` (two dots) — the
        // pitch suffix is a rendering detail the real parser doesn't
        // cross-check against the preceding note, so it's enough to confirm
        // the word has that shape without validating which pitch it names.
        if word.hasPrefix("''"), pitch(fromAbbreviation: String(word.dropFirst(2))) != nil {
            return [.dotMarker(count: 2)]
        }
        if word.hasPrefix("'"), pitch(fromAbbreviation: String(word.dropFirst(1))) != nil {
            return [.dotMarker(count: 1)]
        }
        return [classifyMusicalWord(word)]
    }

    private static func pitch(fromAbbreviation abbrev: String) -> Pitch? {
        switch abbrev.lowercased() {
        case "lg": return .lowG
        case "la": return .lowA
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "hg": return .highG
        case "ha": return .highA
        default: return nil
        }
    }

    private static func splitDurationSuffix(_ word: String) -> (core: String, duration: Double?) {
        for (suffix, value) in durations {
            if word.hasSuffix(suffix), word != suffix {
                return (String(word.dropLast(suffix.count)), value)
            }
        }
        return (word, nil)
    }

    private static func classifyMusicalWord(_ word: String) -> Token {
        let (core, duration) = splitDurationSuffix(word)

        if let p = pitch(fromAbbreviation: core) {
            return .pitch(p, duration: duration)
        }
        if core.uppercased().hasPrefix("REST") {
            return .rest(duration: duration ?? 1.0)
        }
        // A bare trailing 'r'/'l' is a print-layout beam-direction marker
        // glued onto the pitch letters with no separator (e.g. "LAr", "Dl") —
        // meaningless for playback, so strip it and retry as a plain pitch.
        if core.count > 1, "rRlL".contains(core.last!),
           let p = pitch(fromAbbreviation: String(core.dropLast())) {
            return .pitch(p, duration: duration)
        }
        if BWWEmbellishmentTable.contains(core) {
            return .embellishment(.token(core.lowercased()))
        }

        return .unknown(word)
    }
}
