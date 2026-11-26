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
        var titleIsFromExplicitTag = false
        var composerIsFromExplicitTag = false
        var timeSignature = "2/4"
        var explicitTempo: Double?
        var rhythmHint: String?

        let tokens = tokenize(text)
        var pendingEmbellishment: Embellishment?
        var pendingEndingNumbers: Set<Int> = []
        var pendingTieStart = false
        // Duration scale for notes inside an open `^3s`…`^3e`-style
        // bracket (nil when none is open) — applied as each note arrives.
        var openTupletRatio: Double?

        var parts: [TunePart] = []
        var currentMeasures: [Measure] = []
        var currentNotes: [NoteEvent] = []
        var currentMeasureEndingNumbers: Set<Int> = []
        var partHasRepeat = false
        // A repeat can span multiple `&` systems/lines before it actually
        // closes (confirmed against limepipes-plugin-bww's barline handling
        // and a real reference tune) — a part-end barline (`!I`) inside it
        // must NOT flush the part while a repeat is still open; only the
        // matching `''!I` close does.
        var repeatIsOpen = false
        // The open repeat was started with dots (`I!''`), an explicit
        // repeat sign — as opposed to a bare `I!`, which real files use as
        // a plain part-opening barline for parts written out once.
        var repeatOpenedDotted = false

        func flushMeasure() {
            if !currentNotes.isEmpty {
                currentMeasures.append(Measure(notes: currentNotes, endingNumbers: Array(currentMeasureEndingNumbers).sorted()))
                currentNotes.removeAll()
                currentMeasureEndingNumbers.removeAll()
            }
        }
        // Old-style tuplet markers trail the notes they cover, so they scale
        // retroactively — walking back into the last flushed measure if the
        // group happens to straddle a barline.
        func scaleLastNotes(_ count: Int, by ratio: Double) {
            var remaining = count
            var i = currentNotes.count - 1
            while remaining > 0 && i >= 0 {
                currentNotes[i].duration *= ratio
                remaining -= 1
                i -= 1
            }
            guard remaining > 0, var lastMeasure = currentMeasures.last else { return }
            var j = lastMeasure.notes.count - 1
            while remaining > 0 && j >= 0 {
                lastMeasure.notes[j].duration *= ratio
                remaining -= 1
                j -= 1
            }
            currentMeasures[currentMeasures.count - 1] = lastMeasure
        }
        func flushPart() {
            flushMeasure()
            if !currentMeasures.isEmpty {
                // A repeat whose close is missing (a plain `!I`, or another
                // start) still repeats when it opened with repeat dots. (A
                // first ending whose close is missing is handled once the
                // second ending turns up — see `attachingTrailingEndings`.)
                parts.append(TunePart(measures: currentMeasures, hasRepeat: partHasRepeat || (repeatIsOpen && repeatOpenedDotted)))
                currentMeasures.removeAll()
            }
            partHasRepeat = false
            repeatIsOpen = false
            repeatOpenedDotted = false
            // An ending left open by a missing `_'` doesn't leak into the
            // next part.
            pendingEndingNumbers.removeAll()
        }

        /// Whether a `''!I` closes the open repeat before another repeat
        /// starts — decides whether a `!I` written inside it ends the part.
        func repeatClosesLater(after index: Int) -> Bool {
            for token in tokens[(index + 1)...] {
                if case .repeatClose = token { return true }
                if case .repeatOpen(let dotted) = token, dotted { return false }
            }
            return false
        }

        for (tokenIndex, token) in tokens.enumerated() {
            switch token {
            case .comment:
                continue

            case .titledText(let kind, let value, let isPositional):
                switch kind {
                case "T":
                    // An explicit "<title>",(T,...) tag always wins, even
                    // over an earlier positional guess (a bare, untagged
                    // credit/converter-note quote — e.g. "Converted from
                    // BMW Dos file format..." — ahead of the real title in
                    // a real file). A positional guess only fills in when no
                    // explicit tag has claimed the title yet.
                    if !isPositional {
                        title = value
                        titleIsFromExplicitTag = true
                    } else if !titleIsFromExplicitTag && title == "Untitled" {
                        title = value
                    }
                case "M":
                    if !isPositional {
                        composer = value
                        composerIsFromExplicitTag = true
                    } else if !composerIsFromExplicitTag && composer == nil {
                        composer = value
                    }
                case "Y":
                    if rhythmHint == nil { rhythmHint = value }
                default: break // plain annotation text — not needed for playback
                }

            case .meterFraction(let raw):
                timeSignature = raw.replacingOccurrences(of: "_", with: "/")

            case .tempo(let bpm):
                explicitTempo = bpm

            case .signature:
                continue // key signature markers — the fixed chanter scale already bakes these in

            case .pitch(let pitch, let duration):
                var note = NoteEvent(pitch: pitch, duration: (duration ?? (currentNotes.last?.duration ?? 0.5)) * (openTupletRatio ?? 1))
                if let emb = pendingEmbellishment {
                    note.embellishment = emb
                    pendingEmbellishment = nil
                }
                if !pendingEndingNumbers.isEmpty {
                    // Stays "sticky" across notes until an explicit .endEnding
                    // token — an ending typically spans a whole measure, not
                    // just the note immediately after the '1/'2 marker.
                    currentMeasureEndingNumbers.formUnion(pendingEndingNumbers)
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
                currentNotes.append(NoteEvent(pitch: .lowA, duration: duration * (openTupletRatio ?? 1), embellishment: nil, isRest: true))

            case .tupletStart(let ratio):
                openTupletRatio = ratio

            case .tupletClose(let noteCount, let ratio):
                // `^3e` is both the new-style bracket close *and* the
                // old-style trailing marker for a triplet ending on E, so
                // which one it is depends on whether a bracket is open.
                if openTupletRatio != nil {
                    openTupletRatio = nil
                } else {
                    scaleLastNotes(noteCount, by: ratio)
                }

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

            case .repeatOpen(let dotted):
                // A bare `I!` inside a repeat that's already open is a heavy
                // barline at the start of a staff line (real files do this
                // mid-repeat), not a second repeat start.
                if repeatIsOpen && !dotted {
                    flushMeasure()
                    continue
                }
                flushMeasure()
                // A pickup written before the repeat sign (`E_8 I!'' ...`)
                // leads into the part but sits outside the repeat: it stays
                // with the part, played the first time through only.
                // Anything longer than a bar before the sign is a part of
                // its own — a staff line's end (`!t`) no longer closes one,
                // so this has to. The part only repeats if a `''!I` closes
                // it: `I! ... !I` is written out once.
                var leadIn: Measure?
                if currentMeasures.count == 1, currentMeasures[0].endingNumbers.isEmpty,
                   let bar = barBeats(timeSignature),
                   PlayOrder.beats(of: currentMeasures) <= bar + 0.0001 {
                    leadIn = currentMeasures.removeLast()
                    leadIn?.endingNumbers = [1]
                }
                flushPart()
                if let leadIn { currentMeasures.append(leadIn) }
                repeatIsOpen = true
                repeatOpenedDotted = dotted

            case .repeatClose:
                // A close with no open repeats from the start of the part.
                partHasRepeat = true
                repeatIsOpen = false
                // A second ending written after this (`''!I '2 ...`) still
                // belongs to this part — `attachingTrailingEndings` puts it
                // back once the whole tune is parsed.
                flushPart()

            case .partEnd:
                // "End of a part or of the tune" (spec). Real files also put
                // `!I` at the end of a staff line in the middle of a repeat
                // (`I!'' ... !I ... ''!I`) — there it's a heavy barline, and
                // the part runs on to the `''!I`. A repeat that's never
                // closed isn't played twice; its `!I` ends the part.
                if repeatIsOpen && repeatClosesLater(after: tokenIndex) {
                    flushMeasure()
                } else {
                    flushPart()
                }

            case .startEnding(let n):
                // An ending can start mid-bar (`gg LAr_8 gbr LAl_8 '1 ...`):
                // the notes before the marker are played on every pass, so
                // they can't share a measure — and its ending tag — with the
                // notes after it. Otherwise the second time through skips
                // the common half of the bar.
                if currentMeasureEndingNumbers.isEmpty {
                    flushMeasure()
                }
                pendingEndingNumbers.insert(n)

            case .endEnding:
                pendingEndingNumbers.removeAll()

            case .unknown:
                continue
            }
        }
        flushPart()

        if parts.isEmpty {
            parts = [TunePart(measures: [], hasRepeat: false)]
        }

        // TuneTempo states the tempo at the *meter's own natural beat unit*,
        // same as standard Western notation everywhere else: quarter note
        // for simple time (2/4, 3/4, 4/4 — unscaled here, since PipePlayer's
        // internal duration unit already is the quarter-note beat), half
        // note for cut time (2/2 — confirmed directly against a real reel,
        // "Tripping Up The Stairs": TuneTempo,80 under C_ must play at a
        // quarter-note-equivalent 160, not literal 80), and the *dotted*
        // quarter for compound time (6/8, 9/8, 12/8 — confirmed against a
        // real jig, "Biddy From Sligo": TuneTempo,132 under 6_8 must play at
        // a quarter-note-equivalent 198, not literal 132, which dragged
        // badly). An earlier version of this only special-cased cut time;
        // generalizing to the actual rule fixes jigs/slip jigs/etc. too
        // instead of chasing each meter as its own one-off bug report.
        //
        // With no explicit TuneTempo, fall back to the tune type's own
        // conventional default (from the "Y" record, e.g. "Hornpipe.") rather
        // than a single flat number for every dance type — a march and a
        // jig with no stated tempo shouldn't both default to the same speed.
        // This default is itself stated at the meter's natural beat unit,
        // same as an explicit TuneTempo would be, so it gets the identical
        // scaling treatment below.
        let rhythm = rhythmHint.flatMap(TuneRhythm.matching)
        let baseTempo = explicitTempo ?? rhythm?.defaultTempo ?? 90
        let isFreeTempo = rhythmHint.map(TuneRhythm.isFreeTempoGenre) ?? false
        let scaleFactor = isFreeTempo ? 1.0 : Self.tempoScaleFactor(forTimeSignature: timeSignature)
        let tempo = baseTempo * scaleFactor

        return Tune(title: title, composer: composer, tempo: tempo, timeSignature: timeSignature, parts: parts, rhythm: rhythm, tempoScaleFactor: scaleFactor)
            .normalizingEndings()
    }

    /// How many quarter notes long the meter's own natural tempo-marking
    /// beat unit is. Compound meters (6/8, 9/8, 12/8 — numerator a multiple
    /// of 3, greater than 3) are marked at the dotted note of the
    /// denominator's value (3 denominator-units); everything else
    /// (including 3/4, which is simple triple, not compound) is marked at a
    /// single denominator-unit.
    /// One full bar in quarter-note beats, for telling a pickup from a bar.
    static func barBeats(_ timeSignature: String) -> Double? {
        switch timeSignature {
        case "C", "C_", "C|": return 4
        default:
            let parts = timeSignature.split(separator: "/").compactMap { Double($0) }
            guard parts.count == 2, parts[1] > 0 else { return nil }
            return parts[0] * 4 / parts[1]
        }
    }

    static func tempoScaleFactor(forTimeSignature timeSignature: String) -> Double {
        let comps = timeSignature.split(separator: "/")
        guard comps.count == 2, let numerator = Double(comps[0]), let denominator = Double(comps[1]), denominator > 0 else {
            return 1.0
        }
        let denominatorUnitInQuarterNotes = 4.0 / denominator
        let isCompound = numerator > 3 && numerator.truncatingRemainder(dividingBy: 3) == 0
        return isCompound ? 3.0 * denominatorUnitInQuarterNotes : denominatorUnitInQuarterNotes
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
        /// `isPositional` is true for the older bare-quote positional
        /// fallback (no `,(T,...)` tuple at all) — a guess, not a real tag.
        case titledText(kind: String, value: String, isPositional: Bool) // T=title, M=composer, Y=tune type
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
        /// `^3s`-style: opens a tuplet bracket; notes until the close are
        /// scaled by `ratio` as they arrive.
        case tupletStart(ratio: Double)
        /// `^3e` (bracket close) or `^3<pitch>` (old style, trailing the
        /// last of `noteCount` notes) — see the `.tupletClose` handling for
        /// how the two are told apart.
        case tupletClose(noteCount: Int, ratio: Double)
        case embellishment(Embellishment)
        case bar
        /// `I!''` or `I!` — repeat start. `dotted` tells them apart: real
        /// files also use a bare `I!` as a heavy barline inside a repeat.
        case repeatOpen(dotted: Bool)
        /// `''!I` — repeat end; the only sign that makes a part play twice.
        case repeatClose
        /// `!I` — end of a part or of the tune (thin-thick barline). (`!t`, the end of a staff
        /// line, is only a barline: a part routinely runs across several
        /// lines, and treating every line as a part made the progress bar
        /// show parts the file doesn't have.)
        case partEnd
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
                var isPositional = false
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
                    // Real files mix this with properly-tagged lines too — a
                    // single untagged "Converted from BMW Dos..." converter
                    // credit note ahead of a real "<Title>",(T,...) line was
                    // wrongly claiming the title slot positionally; isPositional
                    // marks this a guess so an explicit tag later always wins.
                    let positionalKind = ["T", "Y", "M"]
                    if bareHeaderQuoteCount < positionalKind.count {
                        kindChar = positionalKind[bareHeaderQuoteCount]
                        isPositional = true
                    }
                    bareHeaderQuoteCount += 1
                }
                if let kind = kindChar {
                    tokens.append(.titledText(kind: kind, value: quoted, isPositional: isPositional))
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
        // Barline/repeat tokens, per the BWW format spec (SPEC.md §3.5) —
        // exact matches only. A trailing "t" also ends the staff line, which
        // has no musical meaning. Parts follow the file's own part barlines:
        // "''!I" ends a repeat, "!I" ends a part (or the tune), and
        // "I!''"/"I!" (same thing) start a repeat. "!"/"!!" are plain
        // barlines — a part routinely runs across several staff lines.
        if word == "!" || word == "!t" || word == "!!" || word == "!!t" {
            return [.bar]
        }
        if word == "I!''" || word == "I!" {
            return [.repeatOpen(dotted: word == "I!''")]
        }
        if word == "''!I" || word == "''!It" {
            return [.repeatClose]
        }
        if word == "!I" || word == "!It" {
            return [.partEnd]
        }
        // Endings (§3.6): "'1", "'2", "'22"–"'28" ("2 of n"), "'224" ("2 and
        // 4"). The first digit is the time it's played; for three digits
        // the last is another. "'si"/"'do"/"'bis"/"'intro" brackets don't
        // change playback and fall through as unknown.
        if word.count >= 2, word.hasPrefix("'"), word.dropFirst().allSatisfy(\.isNumber) {
            let digits = word.dropFirst().compactMap(\.wholeNumberValue)
            var times = [digits[0]]
            if digits.count >= 3, let last = digits.last { times.append(last) }
            return times.map { .startEnding($0) }
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
        if let tuplet = tupletToken(word) {
            return [tuplet]
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

    /// BWW tuplets come in two styles: the newer bracket (`^3s` … `^3e`)
    /// and the older trailing marker (`^3hg`, placed after the last note,
    /// naming its pitch). A single digit is the common case — `^2` duplet
    /// (2 in the time of 3), `^3` triplet (3 in the time of 2); two digits
    /// read "N in the time of M" (`^43` = 4 in the time of 3). Previously
    /// unrecognized entirely, so a strathspey's triplet run played at full
    /// written length — half a beat too long per triplet.
    private static func tupletToken(_ word: String) -> Token? {
        guard word.hasPrefix("^") else { return nil }
        let body = word.dropFirst()
        let digits = Array(body.prefix(while: \.isNumber))
        let suffix = String(body.dropFirst(digits.count))
        let count: Int
        let inTimeOf: Int
        switch digits.count {
        case 1:
            switch digits[0] {
            case "2": (count, inTimeOf) = (2, 3)
            case "3": (count, inTimeOf) = (3, 2)
            default: return nil
            }
        case 2:
            guard let n = Int(String(digits[0])), let m = Int(String(digits[1])), n > 0, m > 0 else { return nil }
            (count, inTimeOf) = (n, m)
        default:
            return nil
        }
        let ratio = Double(inTimeOf) / Double(count)
        if suffix == "s" {
            return .tupletStart(ratio: ratio)
        }
        if suffix == "e" || pitch(fromAbbreviation: suffix) != nil {
            return .tupletClose(noteCount: count, ratio: ratio)
        }
        return nil
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
