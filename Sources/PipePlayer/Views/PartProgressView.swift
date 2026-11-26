import SwiftUI

/// A segmented playback-progress view: one segment per part as the file
/// writes it, sized by that part's written length (both endings included)
/// and filling once per pass as it plays, with the current part highlighted.
///
/// All timing comes from `PlayOrder.timeline` — the same play order
/// `MIDIEventBuilder` schedules audio from — so repeats and first/second
/// endings land exactly where they're heard. An earlier version did its
/// own arithmetic, counted every measure on every pass (endings included),
/// and drifted further from the audio after each part with endings.
struct PartProgressView: View {
    let tune: Tune
    let currentTime: TimeInterval
    let tempo: Double
    /// The part being looped, when the loop button is in part mode.
    var loopedPartIndex: Int? = nil
    /// Called with a part's start time when the user clicks its segment —
    /// lets the transport seek straight to the beginning of that part.
    var onSeek: (TimeInterval) -> Void = { _ in }

    private var timeline: [PlayOrder.PartTiming] {
        PlayOrder.timeline(of: tune, tempo: tempo)
    }

    var body: some View {
        let timeline = self.timeline
        let totalBeats = timeline.reduce(0) { $0 + $1.writtenBeats }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let available = max(0, geo.size.width - spacing * CGFloat(max(timeline.count - 1, 0)))
                HStack(spacing: spacing) {
                    ForEach(timeline, id: \.partIndex) { part in
                        let fraction = totalBeats > 0
                            ? part.writtenBeats / totalBeats
                            : 1.0 / Double(max(timeline.count, 1))
                        segment(for: part, width: available * fraction)
                    }
                }
            }
            .frame(height: 32)

            HStack(spacing: 4) {
                if let active = PlayOrder.activePart(in: timeline, at: currentTime),
                   active.partIndex == loopedPartIndex {
                    Image(systemName: "repeat")
                }
                Text(currentPartDescription(timeline))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func segment(for part: PlayOrder.PartTiming, width: CGFloat) -> some View {
        let isActive = currentTime >= part.start && currentTime < part.end
        // A repeated part fills, resets, and fills again — once per pass —
        // each pass measured against its own length, since a first and
        // second ending needn't be the same length.
        let progress = part.passProgress(at: currentTime).fraction
        let isLooped = part.partIndex == loopedPartIndex

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.15))
            GeometryReader { inner in
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: inner.size.width * progress)
            }
            // White only once the fill has reached the label — before that
            // it sits on the empty track, where white all but disappears.
            HStack(spacing: 3) {
                Text("\(part.partIndex + 1)")
                if isLooped {
                    Image(systemName: "repeat")
                }
            }
            .font(.caption2.bold())
            .foregroundStyle(isActive && progress * width > (isLooped ? 36 : 24) ? Color.white : isActive ? Color.accentColor : Color.secondary)
            .padding(.leading, 6)
            if isLooped {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .frame(width: max(0, width))
        .contentShape(Rectangle())
        .onTapGesture { onSeek(part.start) }
        .help(isLooped ? "Part \(part.partIndex + 1) is looping" : "Jump to Part \(part.partIndex + 1)")
    }

    private func currentPartDescription(_ timeline: [PlayOrder.PartTiming]) -> String {
        guard let active = PlayOrder.activePart(in: timeline, at: currentTime) else { return "" }
        var description = "Part \(active.partIndex + 1) of \(timeline.count)"
        if active.hasRepeat {
            let pass = active.passProgress(at: currentTime).pass
            description += pass == 0 ? " (repeat, 1st time)" : " (repeat, 2nd time)"
        }
        return description
    }
}
