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
        // "{g}A3" -> a short High G grace note followed by a dotted-length A.
        #expect(notes.first?.pitch == .highG)
        #expect((notes.first?.duration ?? 1) < 0.1)
        #expect(notes.dropFirst().first?.pitch == .lowA)
        #expect(abs((notes.dropFirst().first?.duration ?? 0) - 1.5) < 0.001)
    }

    @Test func missingKeyFieldThrows() {
        let noKey = "X:1\nT:Bad Tune\nM:4/4\nL:1/8\nA B C D|"
        #expect(throws: (any Error).self) { try ABCParser.parse(noKey) }
    }

    @Test func emptyInputThrows() {
        #expect(throws: (any Error).self) { try ABCParser.parse("   \n  ") }
    }
}
