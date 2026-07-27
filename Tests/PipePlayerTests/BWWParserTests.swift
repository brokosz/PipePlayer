import Testing
@testable import PipePlayer

struct BWWParserTests {

    private let sample = """
    Bagpipe Music Writer Gold:1.0

    "Test Strathspey",(T,L,10,10,Times New Roman,14,0)
    "Trad.",(M,L,10,10,Times New Roman,10,0)
    2_4
    & sharpf sharpc I!''
    ! gg LAr_16 brl LAl_16 thrd B_8 !
    ! dbb_4 LA_8 LG_8 ''!I
    """

    @Test func headerFields() throws {
        let tune = try BWWParser.parse(sample)
        #expect(tune.title == "Test Strathspey")
        #expect(tune.composer == "Trad.")
        #expect(tune.timeSignature == "2/4")
    }

    @Test func beamSuffixedPitchesAndEmbellishmentsParseCorrectly() throws {
        // "LAr_16"/"LAl_16" carry a print-layout beam-direction suffix (r/l)
        // glued onto the pitch letters with no separator — this used to make
        // the parser drop the note entirely (the bug the real Zito the
        // Bubbleman file exposed), so this is the regression test for it.
        let tune = try BWWParser.parse(sample)
        let notes = tune.parts.first?.measures.first?.notes ?? []
        #expect(notes.map(\.pitch) == [.lowA, .lowA, .b])
        #expect(notes.map(\.duration) == [0.25, 0.25, 0.5])
        #expect(notes[0].embellishment == .token("gg"))
        #expect(notes[1].embellishment == .token("brl"))
        #expect(notes[2].embellishment == .token("thrd"))
    }

    @Test func doublingTokenAttachesToNextNote() throws {
        let tune = try BWWParser.parse(sample)
        let notes = tune.parts.first?.measures.last?.notes ?? []
        #expect(notes.first?.pitch == .lowA)
        #expect(notes.first?.embellishment == .token("dbb"))
    }

    @Test func repeatOpenAndCloseMarkPartAsRepeating() throws {
        // "I!''"/"''!I" (confirmed against a real BWW parser) — an earlier
        // version of this parser used a looser "contains !I/I!/!!" match
        // that would have also misfired on a plain "!I" (heavy barline, no
        // repeat) or the never-real "!!" token.
        let tune = try BWWParser.parse(sample)
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].hasRepeat == true)
    }

    @Test func repeatSpanningTwoSystemsStaysOnePart() throws {
        // A repeat can open in one `&` system and only close in the next —
        // an interior system-end ("!t") must not flush the part early.
        let spanning = """
        Bagpipe Music Writer Gold:1.0

        "Spanning",(T,L,10,10,Times New Roman,14,0)
        2_4
        & sharpf sharpc I!''
        ! LA_8 B_8 !t

        & sharpf sharpc
        ! C_8 D_8 ''!I
        """
        let tune = try BWWParser.parse(spanning)
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].hasRepeat == true)
        #expect(tune.parts[0].measures.count == 2)
    }

    @Test func dotMarkerAppliesToPrecedingNote() throws {
        // '<pitch> = one dot (×1.5), ''<pitch> = two dots (×1.75) — the
        // actual dotted-rhythm mechanism (not a tied pair, an earlier
        // misreading of the format).
        let dotted = """
        Bagpipe Music Writer Gold:1.0

        "Dots",(T,L,10,10,Times New Roman,14,0)
        2_4
        & sharpf sharpc
        ! D_8 'd E_16 ''e !
        """
        let tune = try BWWParser.parse(dotted)
        let notes = tune.parts.first?.measures.first?.notes ?? []
        #expect(notes.map(\.pitch) == [.d, .e])
        #expect(abs(notes[0].duration - 0.75) < 0.0001)   // eighth × 1.5
        #expect(abs(notes[1].duration - 0.4375) < 0.0001) // sixteenth × 1.75
    }

    @Test func tieStartAndEndMarkTiedNote() throws {
        // Generic "^ts"/"^te" (no pitch suffix) — confirmed against a real
        // BWW parser; an earlier version of this parser expected a
        // pitch-suffixed "^t<pitch>" token instead, which the reference
        // parser doesn't even implement.
        let tied = """
        Bagpipe Music Writer Gold:1.0

        "Ties",(T,L,10,10,Times New Roman,14,0)
        2_4
        & sharpf sharpc
        ! B_8 ^ts D_8 D_16 ^te E_8 !
        """
        let tune = try BWWParser.parse(tied)
        let notes = tune.parts.first?.measures.first?.notes ?? []
        #expect(notes.map(\.pitch) == [.b, .d, .d, .e])
        #expect(notes[1].isTiedToNext == true)
        #expect(notes[0].isTiedToNext == false)
        #expect(notes[2].isTiedToNext == false)
    }

    @Test func unrecognizedHeaderThrows() {
        #expect(throws: BWWParserError.self) { try BWWParser.parse("not a bww file at all") }
    }

    @Test func legacyBinaryLikeInputThrows() {
        let binaryish = "\u{0001}\u{0002}\u{0003}BMW\u{0000}\u{0001}garbage bytes here"
        do {
            _ = try BWWParser.parse(binaryish)
            Issue.record("Expected BWWParserError.legacyBinaryFormat to be thrown")
        } catch BWWParserError.legacyBinaryFormat {
            // expected
        } catch {
            Issue.record("Expected legacyBinaryFormat, got \(error)")
        }
    }

    @Test func emptyInputThrows() {
        #expect(throws: (any Error).self) { try BWWParser.parse("   ") }
    }

    @Test func tuneTempoParsesWithoutParens() throws {
        // Real files write "TuneTempo,90" (no parens), unlike the other
        // "Name,(...)" metadata blocks — this is the regression test for
        // that off-by-one bug.
        let withTempo = sample.replacingOccurrences(
            of: "& sharpf sharpc I!''",
            with: "TuneTempo,120\n& sharpf sharpc I!''"
        )
        let tune = try BWWParser.parse(withTempo)
        #expect(tune.tempo == 120)
    }
}
