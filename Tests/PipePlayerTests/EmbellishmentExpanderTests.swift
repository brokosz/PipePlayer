import Testing
@testable import PipePlayer

struct EmbellishmentExpanderTests {

    @Test func noEmbellishmentPassesThrough() {
        let note = NoteEvent(pitch: .b, duration: 0.5, embellishment: nil)
        #expect(EmbellishmentExpander.expand(note) == [note])
    }

    @Test func restBypassesExpansionEvenIfTagged() {
        // Defensive: a rest should never actually carry an embellishment, but
        // the expander must not choke on one if it somehow does.
        let rest = NoteEvent(pitch: .lowA, duration: 1.0, embellishment: .token("dbb"), isRest: true)
        #expect(EmbellishmentExpander.expand(rest) == [rest])
    }

    @Test func gracenoteExpandsToGraceThenMainNote() {
        // "gg" = single G (High G) grace note, per BWWEmbellishmentTable.
        let note = NoteEvent(pitch: .d, duration: 0.5, embellishment: .token("gg"))
        let result = EmbellishmentExpander.expand(note)
        #expect(result.count == 2)
        #expect(result[0].pitch == .highG)
        #expect(result[0].duration == EmbellishmentExpander.graceDuration)
        #expect(result[0].embellishment == nil)
        #expect(result[1].pitch == .d)
        #expect(abs(result[1].duration - 0.5) < 0.0001)
        #expect(result[1].embellishment == nil)
    }

    @Test func throwOnDUsesExactTableGraceSequence() {
        // thrd = "gdc" -> Low G, D, C grace notes, then the main note.
        let note = NoteEvent(pitch: .d, duration: 0.75, embellishment: .token("thrd"))
        let result = EmbellishmentExpander.expand(note)
        #expect(result.map(\.pitch) == [.lowG, .d, .c, .d])
        #expect(abs((result.last?.duration ?? 0) - 0.75) < 0.0001)
    }

    @Test func doublingOnBUsesExactTableGraceSequence() {
        // dbb = "Gbd" -> High G, B, D grace notes, then the main note unchanged.
        let note = NoteEvent(pitch: .b, duration: 0.5, embellishment: .token("dbb"))
        let result = EmbellishmentExpander.expand(note)
        #expect(result.map(\.pitch) == [.highG, .b, .d, .b])
        #expect(abs((result.last?.duration ?? 0) - 0.5) < 0.0001)
    }

    @Test func taorluathUsesExactTableGraceSequence() {
        // tar = "gdge" -> a real ornament my earlier hand-derived
        // approximation got wrong (it was missing the trailing E).
        let note = NoteEvent(pitch: .lowA, duration: 0.5, embellishment: .token("tar"))
        let result = EmbellishmentExpander.expand(note)
        #expect(result.map(\.pitch) == [.lowG, .d, .lowG, .e, .lowA])
    }

    @Test func unrecognizedOrnamentFallsBackToConservativeGraceNote() {
        let note = NoteEvent(pitch: .e, duration: 0.5, embellishment: .token("zzznotreal"))
        let result = EmbellishmentExpander.expand(note)
        #expect(result.map(\.pitch) == [.highG, .e])
    }

    @Test func expandTuneFlattensAcrossMeasures() {
        let decorated = NoteEvent(pitch: .b, duration: 0.5, embellishment: .token("grp"))
        let plain = NoteEvent(pitch: .d, duration: 0.5, embellishment: nil)
        let tune = Tune(
            title: "T", composer: nil, tempo: 90, timeSignature: "2/4",
            parts: [TunePart(measures: [Measure(notes: [decorated, plain])], hasRepeat: false)]
        )
        let expanded = EmbellishmentExpander.expand(tune: tune)
        let notes = expanded.parts[0].measures[0].notes
        // grp = lowG, d, lowG grace notes + main B, then the plain D note.
        #expect(notes.map(\.pitch) == [.lowG, .d, .lowG, .b, .d])
    }
}
