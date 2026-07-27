import Foundation

/// Quantizes non-reference voices' measure-by-measure timing to match a
/// single reference voice (the first/primary voice — conventionally the
/// melody), so multiple simultaneous voices (a MusicXML harmony
/// arrangement) can't drift apart over a long tune.
///
/// Each voice parses its own note durations independently, and real-world
/// harmony transcriptions aren't always beat-for-beat consistent between
/// voices even when every voice agrees on the measure count — small
/// differences in how a measure's rhythm sums (a dotted figure here, a
/// simplified passage there) compound measure after measure. Confirmed
/// against a real file ("Hard Times Come Again No More"): all three voices
/// parse to the same 17 measures and match exactly through measure 5, then
/// drift apart by a few hundredths of a beat per measure from measure 6
/// onward — by the end of the tune that's over a second of audible desync
/// between melody and harmony.
///
/// This scales each measure's notes uniformly (not snapped to a fixed
/// grid) so the measure's *total* duration matches the reference voice's
/// same measure — preserving each voice's internal rhythm/feel while
/// guaranteeing every voice starts each measure at the same instant.
/// Deliberately measure-index driven rather than assuming every measure
/// equals the time signature's nominal length, since a pickup/anacrusis
/// measure is *supposed* to be short — as long as every voice's pickup
/// measure agrees with the others (which it does here), that's still
/// correctly preserved rather than stretched out.
enum VoiceAligner {
    static func align(_ voices: [Voice]) -> [Voice] {
        guard voices.count > 1, let reference = voices.first else { return voices }
        let referenceMeasures = reference.tune.parts.flatMap(\.measures)

        return voices.map { voice in
            guard voice.id != reference.id else { return voice }

            var flatIndex = 0
            let newParts: [TunePart] = voice.tune.parts.map { part in
                let newMeasures: [Measure] = part.measures.map { measure in
                    defer { flatIndex += 1 }
                    guard flatIndex < referenceMeasures.count else { return measure }

                    let referenceDuration = totalBeats(of: referenceMeasures[flatIndex])
                    let thisDuration = totalBeats(of: measure)
                    guard thisDuration > 0.0001, referenceDuration > 0.0001 else { return measure }

                    let scale = referenceDuration / thisDuration
                    var scaledMeasure = measure
                    scaledMeasure.notes = measure.notes.map { note in
                        var scaledNote = note
                        scaledNote.duration *= scale
                        return scaledNote
                    }
                    return scaledMeasure
                }
                return TunePart(measures: newMeasures, hasRepeat: part.hasRepeat)
            }

            var alignedTune = voice.tune
            alignedTune.parts = newParts
            return Voice(id: voice.id, name: voice.name, tune: alignedTune)
        }
    }

    private static func totalBeats(of measure: Measure) -> Double {
        measure.notes.reduce(0.0) { $0 + $1.duration * ($1.isDotted ? 1.5 : 1.0) }
    }
}
