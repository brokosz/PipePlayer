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
}
