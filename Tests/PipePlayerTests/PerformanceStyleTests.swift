import Testing
@testable import PipePlayer

struct PerformanceStyleTests {

    private func tune(_ notes: [NoteEvent], rhythm: TuneRhythm?) -> Tune {
        Tune(
            title: "T", composer: nil, tempo: 60, timeSignature: "4/4",
            parts: [TunePart(measures: [Measure(notes: notes)])],
            rhythm: rhythm
        )
    }

    private func notes(of tune: Tune) -> [NoteEvent] {
        tune.parts[0].measures[0].notes
    }

    @Test func strathspeyDotCutIsSharpenedAndKeepsItsTotal() {
        let dotCut = [NoteEvent(pitch: .lowA, duration: 0.75, embellishment: nil),
                      NoteEvent(pitch: .c, duration: 0.25, embellishment: nil)]
        let result = notes(of: PerformanceStyle.apply(to: tune(dotCut, rhythm: .strathspey)))
        #expect(abs(result[0].duration - 5.0 / 6.0) < 0.0001)
        #expect(abs(result[1].duration - 1.0 / 6.0) < 0.0001)
    }

    @Test func strathspeyScotchSnapIsSharpenedTheOtherWay() {
        let snap = [NoteEvent(pitch: .b, duration: 0.25, embellishment: nil),
                    NoteEvent(pitch: .lowA, duration: 0.75, embellishment: nil)]
        let result = notes(of: PerformanceStyle.apply(to: tune(snap, rhythm: .strathspey)))
        #expect(abs(result[0].duration - 1.0 / 6.0) < 0.0001)
        #expect(abs(result[1].duration - 5.0 / 6.0) < 0.0001)
    }

    @Test func evenNotesInAStrathspeyKeepTheirDurations() {
        // Not a 3:1 pair — a triplet run or straight eighths stay as written.
        let eighths = [NoteEvent(pitch: .e, duration: 0.5, embellishment: nil),
                       NoteEvent(pitch: .f, duration: 0.5, embellishment: nil)]
        let result = notes(of: PerformanceStyle.apply(to: tune(eighths, rhythm: .strathspey)))
        #expect(result.map(\.duration) == [0.5, 0.5])
    }

    @Test func otherTuneTypesAreUntouched() {
        let dotCut = [NoteEvent(pitch: .lowA, duration: 0.75, embellishment: nil),
                      NoteEvent(pitch: .c, duration: 0.25, embellishment: nil)]
        for rhythm: TuneRhythm? in [nil, .march, .reel, .hornpipe, .jig] {
            let input = tune(dotCut, rhythm: rhythm)
            #expect(PerformanceStyle.apply(to: input) == input)
        }
    }

    @Test func strathspeyNotesStayConnectedWithNoSilenceBetween() {
        // Pipes and practice chanters never stop sounding between notes —
        // each note-off must land exactly where the next note-on starts.
        let dotCut = [NoteEvent(pitch: .lowA, duration: 0.75, embellishment: nil),
                      NoteEvent(pitch: .c, duration: 0.25, embellishment: nil),
                      NoteEvent(pitch: .e, duration: 1.0, embellishment: nil)]
        let events = MIDIEventBuilder.buildEvents(for: tune(dotCut, rhythm: .strathspey))
        let ons = events.filter { $0.kind == .noteOn }.map(\.time)
        let offs = events.filter { $0.kind == .noteOff }.map(\.time)
        for (off, nextOn) in zip(offs, ons.dropFirst()) {
            #expect(abs(off - nextOn) < 0.0001)
        }
    }

    @Test func bwwStrathspeyCarriesItsRhythmThroughParsing() throws {
        let tune = try BWWParser.parse("""
        Bagpipe Music Writer Gold:1.0

        "Test",(T,L,10,10,Times New Roman,14,0)
        "Strathspey",(Y,C,0,0,Times New Roman,14,0)
        & sharpf sharpc C I!''
        ! LA_4 B_4 C_4 D_4 ''!I
        """)
        #expect(tune.rhythm == .strathspey)
    }
}
