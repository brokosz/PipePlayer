import SwiftUI

/// A segmented playback-progress view: one bar segment per tune part, sized
/// proportionally to that part's length and filling in as it plays, with the
/// currently-playing segment highlighted — replaces an earlier raw
/// note-by-note text listing, which read too much like looking at the
/// source file and not enough like watching the tune play.
///
/// Segment boundaries mirror `MIDIEventBuilder`'s actual play order: a
/// repeated part counts *twice* toward cumulative time before the next part
/// starts, matching real playback. An earlier version used each part's
/// single-pass duration for both the boundary math and the modulo wrap,
/// which was fine for a non-repeating tune but drifted the highlighted
/// segment out of sync with the audio the moment any part actually repeated
/// (i.e. on almost every real tune) — everything after the first repeated
/// part landed a full pass length off. Endings (1st/2nd) are still not
/// tracked per-measure here, only in the real event builder — a small
/// remaining approximation, not the repeat-desync bug this replaces.
struct PartProgressView: View {
    let tune: Tune
    let currentTime: TimeInterval
    let tempo: Double
    /// Called with a part's start time when the user clicks its segment —
    /// lets the transport seek straight to the beginning of that part.
    var onSeek: (TimeInterval) -> Void = { _ in }

    private struct PartSpan {
        let index: Int
        let hasRepeat: Bool
        let start: TimeInterval
        let end: TimeInterval
        let singlePassDuration: TimeInterval
    }

    private var spans: [PartSpan] {
        let secondsPerBeat = 60.0 / max(tempo, 1)
        var result: [PartSpan] = []
        var cursor: TimeInterval = 0
        for (index, part) in tune.parts.enumerated() {
            let start = cursor
            var singlePass: TimeInterval = 0
            for measure in part.measures {
                for note in measure.notes {
                    singlePass += note.duration * secondsPerBeat * (note.isDotted ? 1.5 : 1.0)
                }
            }
            let passCount = part.hasRepeat ? 2.0 : 1.0
            cursor += singlePass * passCount
            result.append(PartSpan(index: index, hasRepeat: part.hasRepeat, start: start, end: cursor, singlePassDuration: singlePass))
        }
        return result
    }

    private var activeSpan: PartSpan? {
        (spans.first { currentTime >= $0.start && currentTime < $0.end }) ?? spans.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(spans, id: \.index) { span in
                        segment(for: span, totalWidth: geo.size.width)
                    }
                }
            }
            .frame(height: 32)

            Text(currentPartDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func segment(for span: PartSpan, totalWidth: CGFloat) -> some View {
        let totalSinglePass = spans.reduce(0) { $0 + $1.singlePassDuration }
        let widthFraction = totalSinglePass > 0
            ? span.singlePassDuration / totalSinglePass
            : 1.0 / Double(max(spans.count, 1))
        let isActive = currentTime >= span.start && currentTime < span.end
        // Within an active repeated part, wrap progress to each individual
        // pass (single-pass length) so the segment visibly fills, resets,
        // and fills again — reflecting that the same material is repeating —
        // rather than only ever showing the first half full.
        let progress: Double = {
            guard span.singlePassDuration > 0 else { return 0 }
            if currentTime < span.start { return 0 }
            if currentTime >= span.end { return 1 }
            let elapsedInSpan = currentTime - span.start
            let withinPass = elapsedInSpan.truncatingRemainder(dividingBy: span.singlePassDuration)
            return withinPass / span.singlePassDuration
        }()

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.15))
            GeometryReader { inner in
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: inner.size.width * progress)
            }
            Text("\(span.index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.leading, 6)
        }
        .frame(width: max(0, totalWidth * widthFraction))
        .contentShape(Rectangle())
        .onTapGesture { onSeek(span.start) }
        .help("Jump to Part \(span.index + 1)")
    }

    private var currentPartDescription: String {
        guard let active = activeSpan else { return "" }
        var description = "Part \(active.index + 1) of \(spans.count)"
        if active.hasRepeat {
            let onSecondPass = (currentTime - active.start) >= active.singlePassDuration
            description += onSecondPass ? " (repeat, 2nd time)" : " (repeat, 1st time)"
        }
        return description
    }
}
