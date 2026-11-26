import Foundation

/// The order a tune's measures are actually played in — repeats unrolled,
/// first and second endings picked per pass. Playback (`MIDIEventBuilder`)
/// and the progress bar (`PartProgressView`) both walk this, so the bar's
/// part boundaries can't drift from what's heard. They used to compute it
/// separately, and the progress bar ignored endings, so every part with a
/// first/second ending ran long and pushed everything after it out of sync.
enum PlayOrder {
    struct Pass: Equatable {
        let partIndex: Int
        /// 1 for the first time through, 2 for a repeat.
        let number: Int
        let measures: [Measure]
    }

    static func passes(of tune: Tune) -> [Pass] {
        tune.parts.enumerated().flatMap { index, part -> [Pass] in
            // A part with no repeat is played once, all of it — an ending
            // marker there has no second pass to choose between, so it's
            // never a reason to skip music.
            guard part.hasRepeat else {
                return [Pass(partIndex: index, number: 1, measures: part.measures)]
            }
            return [1, 2].map { number in
                Pass(partIndex: index, number: number, measures: part.measures.filter {
                    $0.endingNumbers.isEmpty || $0.endingNumbers.contains(number)
                })
            }
        }
    }

    /// How long a note sounds, in beats.
    static func beats(of note: NoteEvent) -> Double {
        note.duration * (note.isDotted ? 1.5 : 1.0)
    }

    static func beats(of measures: [Measure]) -> Double {
        measures.reduce(0) { total, measure in
            measure.notes.reduce(total) { $0 + beats(of: $1) }
        }
    }

    /// Each part's place on the playback timeline.
    struct PartTiming: Equatable {
        let partIndex: Int
        /// Start and end of each pass, in seconds — two for a repeated part.
        let passes: [Range<TimeInterval>]
        /// The part's length on the page, both endings included — what its
        /// segment's width is drawn from.
        let writtenBeats: Double

        var start: TimeInterval { passes.first?.lowerBound ?? 0 }
        var end: TimeInterval { passes.last?.upperBound ?? 0 }
        var hasRepeat: Bool { passes.count > 1 }

        /// Which pass (0-based) is playing at `time`, and how far through
        /// it, 0...1. Before the part: (0, 0). After it: last pass, 1.
        func passProgress(at time: TimeInterval) -> (pass: Int, fraction: Double) {
            guard let first = passes.first, let last = passes.last else { return (0, 0) }
            if time < first.lowerBound { return (0, 0) }
            if time >= last.upperBound { return (passes.count - 1, 1) }
            for (index, range) in passes.enumerated() where time < range.upperBound {
                let length = range.upperBound - range.lowerBound
                return (index, length > 0 ? (time - range.lowerBound) / length : 1)
            }
            return (passes.count - 1, 1)
        }
    }

    /// The part playing at `time`, or the last one once playback is past
    /// the end.
    static func activePart(in timeline: [PartTiming], at time: TimeInterval) -> PartTiming? {
        timeline.first { time >= $0.start && time < $0.end } ?? timeline.last
    }

    static func timeline(of tune: Tune, tempo: Double) -> [PartTiming] {
        let secondsPerBeat = 60.0 / max(tempo, 1)
        var cursor: TimeInterval = 0
        var passRanges: [Int: [Range<TimeInterval>]] = [:]
        for pass in passes(of: tune) {
            let start = cursor
            cursor += beats(of: pass.measures) * secondsPerBeat
            passRanges[pass.partIndex, default: []].append(start..<cursor)
        }
        return tune.parts.indices.map { index in
            PartTiming(
                partIndex: index,
                passes: passRanges[index] ?? [],
                writtenBeats: beats(of: tune.parts[index].measures)
            )
        }
    }
}
