import Testing
import Foundation
@testable import PipePlayer

/// Parts, repeats and endings as the file writes them — and the progress
/// timeline agreeing with what playback schedules.
struct PartStructureTests {

    private func bww(_ body: String) throws -> Tune {
        try BWWParser.parse("""
        Bagpipe Music Writer Gold:1.0

        "Test",(T,L,10,10,Times New Roman,14,0)
        \(body)
        """)
    }

    private func beatsPerPass(_ tune: Tune) -> [Double] {
        PlayOrder.passes(of: tune).map { PlayOrder.beats(of: $0.measures) }
    }

    // MARK: - BWW

    @Test func staffLineBreaksDoNotEndAPart() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I! LA_4 B_4 ! C_4 D_4 !t
        & sharpf sharpc E_4 F_4 ! HG_4 HA_4 !I
        """)
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].measures.count == 4)
        #expect(tune.parts[0].hasRepeat == false)
    }

    @Test func partsFollowRepeatAndPartBarlines() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 D_4 !t
        & sharpf sharpc E_4 F_4 ! HG_4 HA_4 ''!I
        & sharpf sharpc I! LA_4 B_4 ! C_4 D_4 !t
        & sharpf sharpc E_4 F_4 ! HG_4 HA_4 !I
        """)
        #expect(tune.parts.map(\.measures.count) == [4, 4])
        // `I!` starts a repeat like `I!''`, but only `''!I` makes a part
        // play twice — the second part is written out once.
        #expect(tune.parts.map(\.hasRepeat) == [true, false])
    }

    @Test func repeatEndWithNoStartRepeatsFromThePartStart() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 LA_4 B_4 ! C_4 D_4 ''!It
        & sharpf sharpc I!'' E_4 F_4 ''!I
        """)
        #expect(tune.parts.map(\.hasRepeat) == [true, true])
        #expect(tune.parts.map(\.measures.count) == [2, 1])
    }

    @Test func secondEndingAfterTheRepeatSignStaysInItsPartAndPlays() throws {
        // Raigmore's shape: the second ending is written after `''!I`.
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! '1 C_4 D_4 _' ''!I '2 E_4 F_4 _' !t
        & sharpf sharpc I!'' HG_4 HA_4 ''!I
        """)
        #expect(tune.parts.count == 2)
        #expect(tune.parts[0].measures.map(\.endingNumbers) == [[], [1], [2]])
        #expect(beatsPerPass(tune) == [4, 4, 2, 2])
        let pitches = PlayOrder.passes(of: tune).prefix(2)
            .flatMap { $0.measures.flatMap { $0.notes.map(\.pitch) } }
        #expect(pitches == [.lowA, .b, .c, .d, .lowA, .b, .e, .f])
    }

    @Test func endingThatStartsMidBarKeepsTheCommonHalfOnEveryPass() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 '1 D_4 _' ''!I '2 E_4 _' !I
        """)
        #expect(tune.parts.count == 1)
        let passes = PlayOrder.passes(of: tune)
        #expect(passes.map { $0.measures.flatMap { $0.notes.map(\.pitch) } } == [
            [.lowA, .b, .c, .d],
            [.lowA, .b, .c, .e]
        ])
    }

    @Test func secondOfNAndListEndingsFollowTheirFirstDigit() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! '1 C_4 D_4 _' ! '22 E_4 F_4 _' ! '224 HG_4 HA_4 _' ''!I
        """)
        #expect(tune.parts[0].measures.map(\.endingNumbers) == [[], [1], [2], [2, 4]])
    }

    @Test func doubleBarlinesAndBracketsDoNotSplitParts() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 !! 'bis C_4 D_4 bis_' !!t
        & sharpf sharpc E_4 F_4 ''!I
        """)
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].measures.count == 3)
        #expect(tune.parts[0].measures.allSatisfy { $0.endingNumbers.isEmpty })
    }

    @Test func partEndAlwaysEndsAPartEvenAfterARepeatStart() throws {
        // The Pumpkin's Fancy: one `I!` at the top, then `!I` after every
        // four bars. Each `!I` ends a part; none of them repeat.
        let tune = try bww("""
        & sharpf sharpc 2_4 I! LA_4 B_4 ! C_4 D_4 !I
        & sharpf sharpc E_4 F_4 ! HG_4 HA_4 !I
        """)
        #expect(tune.parts.map(\.measures.count) == [2, 2])
        #expect(tune.parts.map(\.hasRepeat) == [false, false])
    }

    @Test func pickupBeforeTheRepeatSignPlaysOnce() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 E_4 I!'' LA_4 B_4 ! C_4 D_4 ''!I
        """)
        #expect(tune.parts.count == 1)
        let passes = PlayOrder.passes(of: tune)
        #expect(passes.map { $0.measures.flatMap { $0.notes.map(\.pitch) } } == [
            [.e, .lowA, .b, .c, .d],
            [.lowA, .b, .c, .d]
        ])
    }

    @Test func aLoneSecondEndingIsIgnored() throws {
        // GEORGE.bmw: a `'22` over the second half of a part with no first
        // ending anywhere. Played in full both times, not half-skipped.
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 '22 D_4 ! E_4 F_4 _' ''!I
        """)
        #expect(beatsPerPass(tune) == [6, 6])
    }

    @Test func firstEndingClosedByPartEndStillRepeats() throws {
        // WAGENBOR.BMW's shape: the first ending ends `!I` instead of
        // `''!I` (bare start here, so only the endings say it repeats).
        let tune = try bww("""
        & sharpf sharpc 2_4 I! LA_4 B_4 !t
        & '1 C_4 D_4 _' !I
        & '2 E_4 F_4 _' !I
        """)
        #expect(tune.parts.count == 1)
        #expect(tune.parts[0].hasRepeat)
        #expect(beatsPerPass(tune) == [4, 4])
    }

    @Test func partEndInsideAClosedRepeatIsJustABarline() throws {
        // First_One_Hundred: `!I` ends a staff line mid-repeat.
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 D_4 !I
        & sharpf sharpc E_4 F_4 ! HG_4 HA_4 ''!I
        """)
        #expect(tune.parts.map(\.measures.count) == [4])
        #expect(tune.parts[0].hasRepeat)
    }

    @Test func bareRepeatStartInsideARepeatIsJustABarline() throws {
        // Piper and the Dead Rabbit: a bare `I!` opens the second staff
        // line of a repeated part.
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 D_4 !t
        & sharpf sharpc I! E_4 F_4 ! HG_4 HA_4 ''!I
        """)
        #expect(tune.parts.map(\.measures.count) == [4])
        #expect(tune.parts[0].hasRepeat)
    }

    @Test func unclosedDottedRepeatStillRepeats() throws {
        // MAIRI BHAN OG: `I!''` opens the part, a plain `!I` closes it.
        // A bare `I!` in the same spot is a part written out once.
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 D_4 !I
        & sharpf sharpc I! E_4 F_4 ! HG_4 HA_4 !I
        """)
        #expect(tune.parts.map(\.hasRepeat) == [true, false])
    }

    @Test func aLoneFirstEndingDoesNotMakeAPartRepeat() throws {
        // "Seconds - Page 1": a `'1` bracket with no second ending.
        let tune = try bww("""
        & sharpf sharpc 2_4 I! '1 LA_4 B_4 _' ! C_4 D_4 !t
        & sharpf sharpc E_4 F_4 !t
        """)
        #expect(tune.parts.map(\.hasRepeat) == [false])
        #expect(beatsPerPass(tune) == [6])
    }

    // MARK: - MusicXML

    @Test func musicXMLSecondEndingAfterBackwardRepeatStaysInItsPart() throws {
        func measure(_ number: Int, _ step: String, left: String = "", right: String = "") -> String {
            """
            <measure number="\(number)">\(number == 1 ? "<attributes><divisions>1</divisions></attributes>" : "")
              \(left)
              <note><pitch><step>\(step)</step><octave>5</octave></pitch><duration>2</duration><type>half</type></note>
              \(right)
            </measure>
            """
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list><score-part id="P1"><part-name>Pipes</part-name></score-part></part-list>
          <part id="P1">
            \(measure(1, "B", left: #"<barline location="left"><repeat direction="forward"/></barline>"#))
            \(measure(2, "C", left: #"<barline location="left"><ending number="1" type="start"/></barline>"#,
                      right: #"<barline location="right"><bar-style>light-heavy</bar-style><ending number="1" type="stop"/><repeat direction="backward"/></barline>"#))
            \(measure(3, "D", left: #"<barline location="left"><ending number="2" type="start"/></barline>"#,
                      right: #"<barline location="right"><bar-style>light-heavy</bar-style><ending number="2" type="discontinue"/></barline>"#))
            \(measure(4, "E"))
          </part>
        </score-partwise>
        """
        let tune = try MusicXMLParser.parse(Data(xml.utf8))
        #expect(tune.parts.count == 2)
        #expect(tune.parts[0].hasRepeat)
        #expect(tune.parts[0].measures.map(\.endingNumbers) == [[], [1], [2]])
        #expect(beatsPerPass(tune) == [4, 4, 2])
    }

    // MARK: - Model and play order

    @Test func trailingEndingsOnlyJoinARepeatedPart() {
        func m(_ endings: [Int]) -> Measure {
            Measure(notes: [NoteEvent(pitch: .lowA, duration: 1, embellishment: nil)], endingNumbers: endings)
        }
        let tune = Tune(title: "T", composer: nil, tempo: 60, timeSignature: "2/4", parts: [
            TunePart(measures: [m([]), m([1])], hasRepeat: true),
            TunePart(measures: [m([2]), m([])], hasRepeat: false),
            TunePart(measures: [m([2])], hasRepeat: false)
        ]).attachingTrailingEndings()
        // The leading ending-2 measure joins the repeat; the rest of that
        // part stays its own. A part that doesn't follow a repeat is left
        // alone.
        #expect(tune.parts.map(\.measures.count) == [3, 1, 1])
    }

    @Test func aPartWithNoRepeatPlaysEveryMeasure() {
        let tune = Tune(title: "T", composer: nil, tempo: 60, timeSignature: "2/4", parts: [
            TunePart(measures: [
                Measure(notes: [NoteEvent(pitch: .lowA, duration: 1, embellishment: nil)], endingNumbers: [2])
            ], hasRepeat: false)
        ])
        #expect(beatsPerPass(tune) == [1])
        #expect(!MIDIEventBuilder.buildEvents(for: tune).isEmpty)
    }

    @Test func timelineEndsWhenPlaybackDoes() throws {
        let tune = try bww("""
        & sharpf sharpc 2_4 I!'' LA_4 B_4 ! C_4 '1 D_4 _' ''!I '2 E_8 F_8 _' !t
        & sharpf sharpc I! HG_4 HA_4 ! LA_2 !I
        """)
        let tempo = 90.0
        let timeline = PlayOrder.timeline(of: tune, tempo: tempo)
        let events = MIDIEventBuilder.buildEvents(for: tune, tempoOverride: tempo)
        #expect(abs((timeline.last?.end ?? 0) - MIDIEventBuilder.totalDuration(of: events)) < 0.0001)
        // Written length counts both endings once; passes count what's played.
        #expect(timeline.map(\.writtenBeats) == [5, 4])
        #expect(timeline[0].passes.count == 2)
        #expect(timeline[1].passes.count == 1)
    }

    @Test func progressFillsEachPassAgainstItsOwnLength() {
        let part = PlayOrder.PartTiming(partIndex: 0, passes: [0..<4, 4..<6], writtenBeats: 5)
        #expect(PartProgressView.passProgress(of: part, at: 2) == (0, 0.5))
        #expect(PartProgressView.passProgress(of: part, at: 5) == (1, 0.5))
        #expect(PartProgressView.passProgress(of: part, at: 7) == (1, 1))
        #expect(PartProgressView.passProgress(of: part, at: -1) == (0, 0))
    }
}
