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
                var aligned = part // keeps hasRepeat and rhythm
                aligned.measures = newMeasures
                return aligned
            }

            var alignedTune = voice.tune
            alignedTune.parts = newParts
            return Voice(id: voice.id, name: voice.name, tune: alignedTune)
        }
    }

    /// Fits a harmony from its own file (band seconds — BWW has no second
    /// voice, so they live apart) to the melody's form, part by part: part
    /// *i* against melody part *i*, taking its repeat, rhythm and tempo.
    /// Seconds files often leave the repeat marks off (Cullen Bay), and
    /// their stated tempo needn't match (Loch Rannoch: 90 against 69).
    ///
    /// Same bar count: each bar takes its melody bar's endings and length.
    /// Different count (Highland Cradle Song, 10 bars against 8 — pickups
    /// and endings written differently): the part is scaled as a whole to
    /// the melody part's written length and plays every pass in full, so
    /// the mismatch can't spill into later parts. Extra harmony parts are
    /// dropped.
    static func fit(_ harmony: Tune, to melody: Tune) -> Tune {
        var fitted = harmony
        fitted.tempo = melody.tempo
        fitted.parts = zip(harmony.parts, melody.parts).map { part, melodyPart in
            var result = part
            result.hasRepeat = melodyPart.hasRepeat
            result.rhythm = melodyPart.rhythm
            if part.measures.count == melodyPart.measures.count {
                result.measures = zip(part.measures, melodyPart.measures).map { measure, melodyMeasure in
                    var scaled = scale(measure, by: totalBeats(of: melodyMeasure), over: totalBeats(of: measure))
                    scaled.endingNumbers = melodyMeasure.endingNumbers
                    return scaled
                }
            } else {
                let target = melodyPart.measures.reduce(0) { $0 + totalBeats(of: $1) }
                let current = part.measures.reduce(0) { $0 + totalBeats(of: $1) }
                result.measures = part.measures.map { measure in
                    var scaled = scale(measure, by: target, over: current)
                    scaled.endingNumbers = []
                    return scaled
                }
            }
            return result
        }
        return fitted
    }

    private static func scale(_ measure: Measure, by target: Double, over current: Double) -> Measure {
        guard current > 0.0001, target > 0.0001 else { return measure }
        var scaled = measure
        scaled.notes = measure.notes.map { note in
            var n = note
            n.duration *= target / current
            return n
        }
        return scaled
    }

    private static func totalBeats(of measure: Measure) -> Double {
        measure.notes.reduce(0.0) { $0 + $1.duration * ($1.isDotted ? 1.5 : 1.0) }
    }
}
