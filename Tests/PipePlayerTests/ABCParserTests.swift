import Testing
@testable import PipePlayer

struct ABCParserTests {

    private let sample = """
    X:1
    T:Test Jig
    C:Trad.
    M:6/8
    L:1/8
    Q:1/4=90
    K:A
    A2A BAG|{g}A3 A2A|
    """

    @Test func headerFields() throws {
        let tune = try ABCParser.parse(sample)
        #expect(tune.title == "Test Jig")
        #expect(tune.composer == "Trad.")
        #expect(tune.timeSignature == "6/8")
        #expect(abs(tune.tempo - 90) < 0.001)
    }

    @Test func firstMeasureNotesAndDurations() throws {
        let tune = try ABCParser.parse(sample)
        let notes = tune.parts.first?.measures.first?.notes ?? []
        #expect(notes.map(\.pitch) == [.lowA, .lowA, .b, .lowA, .lowG])
        // "A2" = 2x default (0.5) = 1.0; the rest are default eighths (0.5).
        #expect(notes.map(\.duration) == [1.0, 0.5, 0.5, 0.5, 0.5])
    }

    @Test func graceNoteGroupInsertsShortLeadingNote() throws {
        let tune = try ABCParser.parse(sample)
        let notes = tune.parts.first?.measures.last?.notes ?? []
        // "{g}A3" -> a short High G grace note followed by a 3x-length A,
        // with the grace's 0.0625 borrowed from that A (1.5 - 0.0625 =
        // 1.4375) rather than added on top of it — see
        // `EmbellishmentExpander`'s identical borrowing for BWW/BMW.
        #expect(notes.first?.pitch == .highG)
        #expect((notes.first?.duration ?? 1) < 0.1)
        #expect(notes.dropFirst().first?.pitch == .lowA)
        #expect(abs((notes.dropFirst().first?.duration ?? 0) - 1.4375) < 0.0001)
    }

    @Test func missingKeyFieldThrows() {
        let noKey = "X:1\nT:Bad Tune\nM:4/4\nL:1/8\nA B C D|"
        #expect(throws: (any Error).self) { try ABCParser.parse(noKey) }
    }

    @Test func emptyInputThrows() {
        #expect(throws: (any Error).self) { try ABCParser.parse("   \n  ") }
    }

    private func body(_ music: String) throws -> Tune {
        try ABCParser.parse("X:1\nT:T\nL:1/8\nM:2/4\nK:HP\n\(music)")
    }

    /// The pitch sequence actually scheduled for playback — repeats unrolled.
    private func playedPitches(_ tune: Tune) -> [Pitch] {
        MIDIEventBuilder.buildEvents(for: tune)
            .filter { $0.kind == .noteOn }
            .compactMap { Pitch(rawValue: Int($0.note)) }
    }

    @Test func repeatSignsMakeARepeatedPart() throws {
        let tune = try body("|:AB|cd:|")
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].hasRepeat)
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d, .lowA, .b, .c, .d])
    }

    @Test func aPickupBeforeTheRepeatPlaysOnce() throws {
        let tune = try body("e2|:AB|cd:|")
        #expect(tune.parts.map(\.hasRepeat) == [false, true])
        #expect(playedPitches(tune) == [.e, .lowA, .b, .c, .d, .lowA, .b, .c, .d])
    }

    @Test func barNumberedEndingsPlayOnTheirOwnPass() throws {
        // The `|1 … :|2` form — about a thousand files in a real collection.
        let tune = try body("|:AB|1cd:|2ef|]")
        #expect(tune.parts[0].measures.map(\.endingNumbers) == [[], [1], [2]])
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d, .lowA, .b, .e, .f])
    }

    @Test func bracketedEndingsPlayOnTheirOwnPass() throws {
        // The `[1 … ]:|[2 … ]|` form, from a real file ("Charlie MacDonald").
        let tune = try body("|:AB|[1 cd ]:|[2 ef ]|")
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d, .lowA, .b, .e, .f])
    }

    @Test func musicAfterASecondEndingPlaysOnceAfterTheRepeat() throws {
        let tune = try body("|:AB|1cd:|2ef|ga|]")
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d, .lowA, .b, .e, .f, .highG, .highA])
    }

    @Test func doubleColonClosesOneRepeatAndOpensTheNext() throws {
        let tune = try body("|:AB::cd:|")
        #expect(tune.parts.map(\.hasRepeat) == [true, true])
        #expect(playedPitches(tune) == [.lowA, .b, .lowA, .b, .c, .d, .c, .d])
    }

    @Test func aSecondEndingWithNoFirstIsIgnored() throws {
        // Real converter output ("Miss Ada Crawford"): a stray `:|2` before
        // any music used to tag the whole part second-time-only, so it
        // played once instead of twice.
        let tune = try body(":|2 A|Bc|de:|")
        #expect(tune.parts.allSatisfy { $0.measures.allSatisfy { $0.endingNumbers.isEmpty } })
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d, .e, .lowA, .b, .c, .d, .e])
    }

    @Test func aHeaderOnlyFirstTuneNamesTheSet() throws {
        // Real file ("Grade III MEDLEY 2002"): X:1 is just the set's title.
        let tune = try ABCParser.parse("""
        X:1
        T:Grade III MEDLEY
        K:HP

        X:2
        T:Charlie MacDonald
        L:1/8
        M:2/4
        Q:86
        K:HP
        cd|

        X:3
        T:The Next One
        L:1/8
        M:2/4
        Q:86
        K:HP
        ef|
        """)
        #expect(tune.title == "Grade III MEDLEY")
        #expect(tune.tempo == 86)
        #expect(tune.parts.count == 2)
    }

    @Test func inlineFieldsAreNotReadAsRepeatSigns() throws {
        // `[M:C|]`'s colon used to be a candidate repeat sign.
        let tune = try body("AB|[M:C|]cd|")
        #expect(tune.parts.allSatisfy { !$0.hasRepeat })
        #expect(playedPitches(tune) == [.lowA, .b, .c, .d])
    }

    @Test func bareTempoInCutTimeIsReadAtTheHalfNote() throws {
        // Real file ("The Blackbird"): Q:102 under M:C| means 102 half
        // notes a minute. Read as quarters, the reel played at half speed.
        let tune = try ABCParser.parse("""
        X:1
        T:The Blackbird
        R:REEL
        L:1/8
        M:C|
        Q:102
        K:HP
        e4|ag|
        """)
        #expect(tune.timeSignature == "2/2")
        #expect(tune.tempo == 204)
        #expect(tune.tempoScaleFactor == 2)
    }

    @Test func bareTempoInCompoundTimeIsReadAtTheDottedQuarter() throws {
        let tune = try ABCParser.parse("X:1\nT:J\nR:JIG\nL:1/8\nM:6/8\nQ:120\nK:HP\nABc|")
        #expect(tune.tempo == 180)
        #expect(tune.tempoScaleFactor == 1.5)
    }

    @Test func bareTempoForASlowAirIsNotScaled() throws {
        let tune = try ABCParser.parse("X:1\nT:A\nR:SLOW AIR\nL:1/8\nM:6/8\nQ:60\nK:HP\nABc|")
        #expect(tune.tempo == 60)
        #expect(tune.tempoScaleFactor == 1)
    }

    @Test func tempoWithAnExplicitNoteValueIsTakenAsWritten() throws {
        let tune = try ABCParser.parse("X:1\nT:J\nL:1/8\nM:6/8\nQ:3/8=120\nK:HP\nABc|")
        #expect(tune.tempo == 180)
        #expect(tune.tempoScaleFactor == 1.5)
    }

    @Test func commonTimeIsNormalized() throws {
        let tune = try ABCParser.parse("X:1\nT:S\nL:1/8\nM:C\nQ:130\nK:HP\nABcd|")
        #expect(tune.timeSignature == "4/4")
        #expect(tune.tempo == 130)
    }

    @Test func partLabelsInTheBodyAreNotNotesAndStartANewPart() throws {
        // `P:A` used to come through as a stray low A.
        let tune = try ABCParser.parse("""
        X:1
        T:T
        L:1/8
        M:2/4
        K:HP
        P:A
        cd|
        P:B
        ef|
        """)
        #expect(tune.parts.count == 2)
        #expect(tune.parts.flatMap(\.measures).flatMap(\.notes).map(\.pitch) == [.c, .d, .e, .f])
    }

    @Test func aSetPlaysEachTuneAtItsOwnTempo() throws {
        // Real file ("The Blackbird set"): reels at Q:102 in C|, then a
        // hornpipe at Q:102 in 2/4 with L:1/16 — previously the hornpipe
        // inherited the reel's L:1/8 (double-length notes) and the later
        // tunes' header lines were parsed as notes.
        let tune = try ABCParser.parse("""
        X:1
        T:The Blackbird
        R:REEL
        L:1/8
        M:C|
        Q:102
        K:HP
        cd|

        X:2
        T:Andy Renwick's Favourite Ferret
        C:Gordon Duncan
        R:HORNPIPE
        L:1/16
        M:2/4
        Q:102
        K:HP
        ef|
        """)
        #expect(tune.title == "The Blackbird / Andy Renwick's Favourite Ferret")
        #expect(tune.composer == "Gordon Duncan")
        #expect(tune.tempo == 204) // the lead reel, at the half note
        #expect(tune.parts.count == 2)
        let notes = tune.parts.flatMap(\.measures).flatMap(\.notes)
        #expect(notes.map(\.pitch) == [.c, .d, .e, .f]) // no header text read as notes
        // Reel eighths: 0.5 beats at 204. Hornpipe sixteenths: 0.25 beats
        // at its own 102, stretched ×2 to sound right at the set's 204.
        #expect(notes.map(\.duration) == [0.5, 0.5, 0.5, 0.5])
        #expect(tune.parts.map(\.rhythm) == [.reel, .hornpipe])
    }

    @Test func missingTempoFallsBackToRhythmDefaultScaledForCompoundMeter() throws {
        // No Q: field at all — falls back to R:'s tune-type default (118 for
        // a jig), scaled the same way an explicit compound-meter tempo would
        // be (118 * 1.5 = 177), so the same tune type ends up at the same
        // real speed whether it came from ABC or BWW.
        let jigNoTempo = """
        X:1
        T:Test Jig
        M:6/8
        L:1/8
        R:Jig
        K:A
        A2A BAG|
        """
        let tune = try ABCParser.parse(jigNoTempo)
        #expect(abs(tune.tempo - 177) < 0.001)
    }

    @Test func explicitTempoWinsOverRhythmDefault() throws {
        let jigWithTempo = """
        X:1
        T:Test Jig
        M:6/8
        L:1/8
        R:Jig
        Q:1/4=150
        K:A
        A2A BAG|
        """
        let tune = try ABCParser.parse(jigWithTempo)
        #expect(abs(tune.tempo - 150) < 0.001)
    }

    @Test func unrecognizedRhythmFallsBackToFlatDefault() throws {
        let noHint = """
        X:1
        T:Test Tune
        M:2/4
        L:1/8
        K:A
        A2A BAG|
        """
        let tune = try ABCParser.parse(noHint)
        #expect(abs(tune.tempo - 90) < 0.001)
    }

    private func firstMeasure(_ body: String) throws -> [NoteEvent] {
        let tune = try ABCParser.parse("X:1\nT:B\nM:4/4\nL:1/8\nK:HP\n\(body)\n")
        return tune.parts.first?.measures.first?.notes ?? []
    }

    @Test func brokenRhythmDotsTheFirstAndHalvesTheSecond() throws {
        let notes = try firstMeasure("A>B c<d e>>f g<<a|")
        #expect(notes.map(\.duration) == [0.75, 0.25, 0.25, 0.75, 0.875, 0.125, 0.125, 0.875])
        #expect(notes.allSatisfy { !$0.isDotted })
    }

    @Test func brokenRhythmCarriesAcrossARest() throws {
        let notes = try firstMeasure("A>z B2 c2 d2|")
        #expect(notes.map(\.duration) == [0.75, 0.25, 1.0, 1.0, 1.0])
    }

    @Test func brokenRhythmBarAddsUpToTheMeter() throws {
        let notes = try firstMeasure("A>B c>d e>f g>a|")
        #expect(notes.reduce(0) { $0 + $1.duration } == 4.0)
    }
}
