import SwiftUI

/// A set's tunes, in play order — shown only in a tab holding a set.
/// Clicking a row jumps to that tune; rows drag to reorder; + adds tunes
/// and − removes the selected one.
struct SetListView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var engine: PlaybackEngine
    @State private var selection: UUID?

    var body: some View {
        let entries = appState.setList?.entries ?? []
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { number, entry in
                    row(number: number + 1, entry: entry)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        // Every click jumps, even on the row already
                        // selected; selection itself only picks what − removes.
                        .simultaneousGesture(TapGesture().onEnded { jump(to: entry.id) })
                }
                .onMove { appState.moveSetEntries(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            // At least a few rows; grows with the window.
            .frame(minHeight: min(max(CGFloat(entries.count), 2) * 24 + 8, 128), maxHeight: .infinity)
            .overlay {
                if entries.isEmpty {
                    Text("Add tunes with + or drop them here")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                Button {
                    appState.addToSet(urls: AppState.chooseSetTuneFiles())
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 20)
                }
                .help("Add tunes to the set")
                Divider().frame(height: 16)
                Button {
                    if let selection { appState.removeFromSet(id: selection) }
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .disabled(selection == nil)
                .help("Remove the selected tune")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }

    private func jump(to id: UUID) {
        guard let segment = appState.segmentIndex(ofEntry: id),
              engine.segmentStarts.indices.contains(segment) else { return }
        engine.seek(to: engine.segmentStarts[segment])
    }

    private func row(number: Int, entry: SetList.Entry) -> some View {
        let segment = appState.segmentIndex(ofEntry: entry.id)
        let problem = appState.entryProblems[entry.id]
        let isPlaying = segment != nil && segment == engine.currentSegmentIndex && !engine.segments.isEmpty
        return HStack(spacing: 8) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Color.accentColor)
                .opacity(isPlaying && engine.state == .playing ? 1 : 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(title(of: entry, segment: segment))
                    .fontWeight(isPlaying ? .semibold : .regular)
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let segment, engine.segments.indices.contains(segment) {
                let tune = engine.segments[segment]
                Text("\(Int((tune.tempo / tune.displayTempoScaleFactor).rounded()))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(problem == nil ? 1 : 0.5)
    }

    private func title(of entry: SetList.Entry, segment: Int?) -> String {
        if let segment, appState.segmentTitles.indices.contains(segment) {
            return appState.segmentTitles[segment]
        }
        let file = entry.relativePath.map { ($0 as NSString).lastPathComponent } ?? "Tune"
        return (file as NSString).deletingPathExtension
    }
}
