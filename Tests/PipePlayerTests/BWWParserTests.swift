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

    @Test func explicitTitleTagWinsOverEarlierBareConverterNote() throws {
        // Real file found in the wild ("Brest St. Marc"): a bare, untagged
        // credit line ("Converted from BMW Dos file format to Bagpipe
        // Reader 1.0 format using BMWFC32.") with no ",(T,...)" tuple at all
        // precedes the real, properly-tagged title line. The older
        // bare-quote positional fallback (built for files with NO tagged
        // lines anywhere) was wrongly claiming that converter note as the
        // title positionally, then refusing to let the real tagged title
        // overwrite it.
        let withConverterNote = """
        Bagpipe Reader:1.0

        "Converted from  BMW Dos file format to Bagpipe Reader 1.0 format using BMWFC32."

        "Brest St. Marc",(T,L,0,0,Times New Roman,16,700,0,0,18,0,0,0)

        "6/8 and 7/8 Jig",(Y,C,0,0,Times New Roman,14,400,0,0,18,0,0,0)

        "",(M,R,0,0,Times New Roman,14,400,0,0,18,0,0,0)

        TuneTempo,90
        & sharpf sharpc 6_8 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(withConverterNote)
        #expect(tune.title == "Brest St. Marc")
        #expect(tune.composer == "")
    }

    @Test func positionalTitleStillWorksWithNoTagsAtAllInFile() throws {
        // The older plain-positional convention itself (a file with NO
        // tagged lines anywhere) must keep working — this isn't a case of
        // "always ignore bare quotes," only "an explicit tag outranks a
        // positional guess."
        let untaggedFile = """
        Bagpipe Reader:1.0

        "Untagged Title"

        "March"

        "A. Composer"

        TuneTempo,90
        & sharpf sharpc 2_4 I!''
        ! LA_8 B_8 !
        ! C_8 D_8 ''!I
        """
        let tune = try BWWParser.parse(untaggedFile)
        #expect(tune.title == "Untagged Title")
        #expect(tune.composer == "A. Composer")
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

    @Test func cutTimeDoublesTuneTempo() throws {
        // Real reel found in the wild ("Tripping Up The Stairs"):
        // TuneTempo,80 under "C_" (cut time / alla breve, timeSignature
        // "2/2") must play at quarter-note-equivalent 160, not literal 80 —
        // cut time conventionally states tempo at the half-note pulse.
        // Confirmed directly by ear against a real cut-time reel; every
        // other meter uses TuneTempo exactly as written (see the 2/4
        // `tuneTempoParsesWithoutParens` case above, unaffected by this).
        let cutTimeTune = """
        Bagpipe Music Writer Gold:1.0

        "Test Reel",(T,L,10,10,Times New Roman,14,0)
        TuneTempo,80
        C_
        & sharpf sharpc I!''
        ! LA_8 B_8 !
        ! C_8 D_8 ''!I
        """
        let tune = try BWWParser.parse(cutTimeTune)
        #expect(tune.timeSignature == "2/2")
        #expect(tune.tempo == 160)
    }

    @Test func nonCutTimeMeterLeavesTempoUnscaled() throws {
        let commonTimeTune = """
        Bagpipe Music Writer Gold:1.0

        "Test March",(T,L,10,10,Times New Roman,14,0)
        TuneTempo,80
        C
        & sharpf sharpc I!''
        ! LA_8 B_8 !
        ! C_8 D_8 ''!I
        """
        let tune = try BWWParser.parse(commonTimeTune)
        #expect(tune.timeSignature == "4/4")
        #expect(tune.tempo == 80)
    }

    @Test func compoundMeterScalesTuneTempoByOnePointFive() throws {
        // Real jig found in the wild ("Biddy From Sligo"): TuneTempo,132
        // under "6_8" must play at quarter-note-equivalent 198, not literal
        // 132 — 6/8 (like 9/8, 12/8) is compound time, conventionally
        // marked at the dotted-quarter pulse (1.5 quarter notes), the same
        // general rule that makes cut time ×2, generalized rather than
        // treated as its own one-off special case.
        let jigTune = """
        Bagpipe Music Writer Gold:1.0

        "Test Jig",(T,L,10,10,Times New Roman,14,0)
        TuneTempo,132
        & sharpf sharpc 6_8 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(jigTune)
        #expect(tune.timeSignature == "6/8")
        #expect(tune.tempo == 198)
    }

    @Test func simpleTripleMeterLeavesTempoUnscaled() throws {
        // 3/4 is simple triple (three individual quarter-note beats), not
        // compound, even though the numerator is a multiple of 3 — must not
        // be scaled the way 6/8 or 9/8 are.
        let waltzTune = """
        Bagpipe Music Writer Gold:1.0

        "Test Waltz",(T,L,10,10,Times New Roman,14,0)
        TuneTempo,90
        & sharpf sharpc 3_4 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(waltzTune)
        #expect(tune.timeSignature == "3/4")
        #expect(tune.tempo == 90)
    }

    @Test func nineEightSlipJigScalesTuneTempoByOnePointFive() throws {
        let slipJigTune = """
        Bagpipe Music Writer Gold:1.0

        "Test Slip Jig",(T,L,10,10,Times New Roman,14,0)
        TuneTempo,140
        & sharpf sharpc 9_8 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(slipJigTune)
        #expect(tune.timeSignature == "9/8")
        #expect(tune.tempo == 210)
    }

    @Test func missingTuneTempoFallsBackToRhythmDefault() throws {
        // No TuneTempo record at all — falls back to the "Y" tune-type
        // record's own conventional default (118 for a jig) rather than a
        // flat 90 for every dance type, then gets the same compound-meter
        // scaling an explicit TuneTempo would (118 * 1.5 = 177).
        let jigNoTempo = """
        Bagpipe Music Writer Gold:1.0

        "Test Jig",(T,L,10,10,Times New Roman,14,0)
        "Jig",(Y,C,0,0,Times New Roman,14,0)
        & sharpf sharpc 6_8 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(jigNoTempo)
        #expect(tune.tempo == 177)
    }

    @Test func explicitTuneTempoWinsOverRhythmDefault() throws {
        let jigWithTempo = """
        Bagpipe Music Writer Gold:1.0

        "Test Jig",(T,L,10,10,Times New Roman,14,0)
        "Jig",(Y,C,0,0,Times New Roman,14,0)
        TuneTempo,132
        & sharpf sharpc 6_8 I!''
        ! LA_8 B_8 C_8 !
        ! D_8 E_8 F_8 ''!I
        """
        let tune = try BWWParser.parse(jigWithTempo)
        #expect(tune.tempo == 198)
    }

    @Test func unrecognizedRhythmHintFallsBackToFlatDefault() throws {
        let noHintTune = """
        Bagpipe Music Writer Gold:1.0

        "Test Tune",(T,L,10,10,Times New Roman,14,0)
        & sharpf sharpc 2_4 I!''
        ! LA_8 B_8 !
        ! C_8 D_8 ''!I
        """
        let tune = try BWWParser.parse(noHintTune)
        #expect(tune.tempo == 90)
    }
}
