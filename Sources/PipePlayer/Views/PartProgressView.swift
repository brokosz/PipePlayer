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
    /// Every part in play order, timed as heard (`PlaybackEngine.partTimeline`).
    let timeline: [PlayOrder.PartTiming]
    let currentTime: TimeInterval
    /// Position in `timeline` of the part being looped, in part loop mode.
    var loopedPartIndex: Int? = nil
    /// A set's tune titles, in order; empty for a single tune.
    var tuneTitles: [String] = []
    /// Called with a part's start time when the user clicks its segment —
    /// lets the transport seek straight to the beginning of that part.
    var onSeek: (TimeInterval) -> Void = { _ in }

    var body: some View {
        let totalBeats = timeline.reduce(0) { $0 + $1.writtenBeats }
        let spacing: CGFloat = 3
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let available = max(0, geo.size.width - spacing * CGFloat(max(timeline.count - 1, 0)))
                let width: (PlayOrder.PartTiming) -> CGFloat = { part in
                    available * (totalBeats > 0 ? part.writtenBeats / totalBeats : 1.0 / Double(max(timeline.count, 1)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !tuneTitles.isEmpty {
                        tuneTitleRow(width: width, spacing: spacing)
                    }
                    HStack(spacing: spacing) {
                        ForEach(Array(timeline.enumerated()), id: \.offset) { position, part in
                            segment(for: part, at: position, width: width(part))
                        }
                    }
                    .frame(height: 32)
                }
            }
            .frame(height: tuneTitles.isEmpty ? 32 : 52)

            HStack(spacing: 4) {
                if let active = activePosition, active == loopedPartIndex {
                    Image(systemName: "repeat")
                }
                Text(currentPartDescription)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Position in `timeline` of the part at the playhead.
    private var activePosition: Int? {
        guard !timeline.isEmpty else { return nil }
        return timeline.firstIndex { currentTime >= $0.start && currentTime < $0.end } ?? timeline.count - 1
    }

    private var activeTuneIndex: Int? {
        activePosition.map { timeline[$0].tuneIndex }
    }

    /// One title per tune, spanning that tune's part segments.
    private func tuneTitleRow(width: @escaping (PlayOrder.PartTiming) -> CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(tuneTitles.enumerated()), id: \.offset) { tuneIndex, title in
                let parts = timeline.filter { $0.tuneIndex == tuneIndex }
                let span = parts.reduce(0) { $0 + width($1) } + spacing * CGFloat(max(parts.count - 1, 0))
                if !parts.isEmpty {
                    Text(title)
                        .font(.caption.weight(tuneIndex == activeTuneIndex ? .semibold : .regular))
                        .foregroundStyle(tuneIndex == activeTuneIndex ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: max(0, span), alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onSeek(parts[0].start) }
                }
            }
        }
        .frame(height: 16)
    }

    private func segment(for part: PlayOrder.PartTiming, at position: Int, width: CGFloat) -> some View {
        let isActive = currentTime >= part.start && currentTime < part.end
        // A repeated part fills, resets, and fills again — once per pass —
        // each pass measured against its own length, since a first and
        // second ending needn't be the same length.
        let progress = part.passProgress(at: currentTime).fraction
        let isLooped = position == loopedPartIndex

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

    private var currentPartDescription: String {
        guard let position = activePosition else { return "" }
        let active = timeline[position]
        let partCount = timeline.filter { $0.tuneIndex == active.tuneIndex }.count
        var description = "Part \(active.partIndex + 1) of \(partCount)"
        if active.hasRepeat {
            let pass = active.passProgress(at: currentTime).pass
            description += pass == 0 ? " (repeat, 1st time)" : " (repeat, 2nd time)"
        }
        if !tuneTitles.isEmpty {
            description = "Tune \(active.tuneIndex + 1) of \(tuneTitles.count) · " + description
        }
        return description
    }
}
