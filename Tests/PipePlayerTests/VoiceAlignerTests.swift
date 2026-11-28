import Testing
@testable import PipePlayer

struct VoiceAlignerTests {

    private func note(_ pitch: Pitch, _ duration: Double) -> NoteEvent {
        NoteEvent(pitch: pitch, duration: duration, embellishment: nil)
    }

    @Test func nonReferenceVoiceMeasureIsScaledToMatchReference() throws {
        // Reference (melody) measure 2 sums to 4.0 beats; the second voice's
        // measure 2 sums to only 3.8 — a real-world rounding/transcription
        // mismatch, not a genuine pickup measure. Its notes should be scaled
        // by 4.0/3.8 so the measure lands on the same total duration.
        let melody = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
            parts: [TunePart(measures: [
                Measure(notes: [note(.lowG, 1), note(.lowA, 1), note(.b, 1), note(.c, 1)]) // 4.0
            ])]
        )
        let harmony = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
            parts: [TunePart(measures: [
                Measure(notes: [note(.d, 1.9), note(.e, 1.9)]) // 3.8
            ])]
        )
        let voices = [
            Voice(id: "melody", name: "Melody", tune: melody),
            Voice(id: "harm1", name: "Harmony", tune: harmony)
        ]

        let aligned = VoiceAligner.align(voices)
        #expect(aligned[0].tune == melody) // reference untouched
        let scaledNotes = aligned[1].tune.parts[0].measures[0].notes
        let scaledTotal = scaledNotes.reduce(0.0) { $0 + $1.duration }
        #expect(abs(scaledTotal - 4.0) < 0.0001)
        #expect(abs(scaledNotes[0].duration - 2.0) < 0.0001) // 1.9 * (4.0/3.8)
    }

    @Test func matchingPickupMeasuresAreLeftAsIs() throws {
        // Both voices agree their first (pickup) measure is short — that's
        // a legitimate anacrusis, not drift, so no scaling should occur.
        let melody = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
            parts: [TunePart(measures: [Measure(notes: [note(.lowG, 0.5)])])]
        )
        let harmony = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
            parts: [TunePart(measures: [Measure(notes: [note(.d, 0.5)])])]
        )
        let aligned = VoiceAligner.align([
            Voice(id: "melody", name: "Melody", tune: melody),
            Voice(id: "harm1", name: "Harmony", tune: harmony)
        ])
        #expect(aligned[1].tune.parts[0].measures[0].notes[0].duration == 0.5)
    }

    @Test func singleVoiceIsUnaffected() throws {
        let melody = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "4/4",
            parts: [TunePart(measures: [Measure(notes: [note(.lowG, 1)])])]
        )
        let voices = [Voice(id: "melody", name: "Melody", tune: melody)]
        #expect(VoiceAligner.align(voices) == voices)
    }

    // MARK: - fit(_:to:) — a harmony file fitted to the melody part by part

    private func bars(_ count: Int, beats: Int = 2, endings: [Int: [Int]] = [:]) -> [Measure] {
        (0..<count).map { i in
            Measure(notes: Array(repeating: note(.lowA, 1), count: beats), endingNumbers: endings[i] ?? [])
        }
    }

    private func tune(_ parts: [TunePart], tempo: Double = 90) -> Tune {
        Tune(title: "T", composer: nil, tempo: tempo, timeSignature: "2/4", parts: parts)
    }

    @Test func fitTakesTheMelodysRepeats() {
        let melody = tune([TunePart(measures: bars(4), hasRepeat: true), TunePart(measures: bars(4), hasRepeat: true)])
        let harmony = tune([TunePart(measures: bars(4)), TunePart(measures: bars(4))])
        let fitted = VoiceAligner.fit(harmony, to: melody)
        #expect(fitted.parts.allSatisfy { $0.hasRepeat })
    }

    @Test func fitTakesTheMelodysEndings() {
        let melody = tune([TunePart(measures: bars(4, endings: [2: [1], 3: [2]]), hasRepeat: true)])
        let harmony = tune([TunePart(measures: bars(4))])
        let fitted = VoiceAligner.fit(harmony, to: melody)
        #expect(fitted.parts[0].measures.map { $0.endingNumbers } == [[], [], [1], [2]])
    }

    @Test func fitScalesAMismatchedPartAsAWhole() {
        let melody = tune([TunePart(measures: bars(10, endings: [9: [2]]), hasRepeat: true)])
        let harmony = tune([TunePart(measures: bars(8, endings: [7: [2]]))])
        let fitted = VoiceAligner.fit(harmony, to: melody)
        let part = fitted.parts[0]
        #expect(part.measures.count == 8)
        #expect(abs(PlayOrder.beats(of: part.measures) - 20) < 0.0001)
        #expect(part.measures.allSatisfy { $0.endingNumbers.isEmpty })
        #expect(part.hasRepeat)
    }

    @Test func fitDropsExtraHarmonyParts() {
        let melody = tune([TunePart(measures: bars(2)), TunePart(measures: bars(2))])
        let harmony = tune([TunePart(measures: bars(2)), TunePart(measures: bars(2)), TunePart(measures: bars(2))])
        #expect(VoiceAligner.fit(harmony, to: melody).parts.count == 2)
    }

    @Test func fitUsesTheMelodysTempo() {
        let melody = tune([TunePart(measures: bars(2))], tempo: 69)
        let harmony = tune([TunePart(measures: bars(2))], tempo: 90)
        #expect(VoiceAligner.fit(harmony, to: melody).tempo == 69)
    }

    @Test func fitLeavesAnEmptyPartAlone() {
        let melody = tune([TunePart(measures: bars(2))])
        let harmony = tune([TunePart(measures: [])])
        #expect(VoiceAligner.fit(harmony, to: melody).parts[0].measures.isEmpty)
    }
}

