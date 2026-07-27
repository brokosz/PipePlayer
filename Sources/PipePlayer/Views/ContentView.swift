import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var engine: PlaybackEngine
    @State private var isTargetedForDrop = false

    init(appState: AppState) {
        self.appState = appState
        self.engine = appState.engine
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            if let tune = appState.tune {
                PartProgressView(tune: tune, currentTime: engine.currentTime, tempo: engine.tempo)
                if engine.voices.count > 1 {
                    VoiceMuteControlsView(engine: engine)
                }
                TransportControlsView(engine: engine)
            } else {
                emptyState
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 460)
        .background(dropHighlightOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
        .alert(
            "Couldn't open file",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(appState.tune?.title ?? "PipePlayer")
                    .font(.title2).bold()
                if let composer = appState.tune?.composer, !composer.isEmpty {
                    Text(composer).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Open…") { appState.presentOpenPanel() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open or drop an .abc, .bww, .bmw, .musicxml, or .mxl file to play it.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dropHighlightOverlay: some View {
        if isTargetedForDrop {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: URL.self) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async { appState.open(url: url) }
            }
        }
        return true
    }
}
