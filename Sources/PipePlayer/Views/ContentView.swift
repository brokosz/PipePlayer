import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // Owned here, per window/tab — previously a single instance shared by
    // the whole app (declared once on `PipePlayerApp`), which meant every
    // tab showed and controlled the exact same tune; a second tab wasn't an
    // independent tune at all, just another view onto the same one (most
    // visibly, they all showed whichever tune was opened *last* in their
    // window title). Each window now gets its own `AppState`/`PlaybackEngine`;
    // `PlaybackCoordinator` (see `PlaybackEngine.play()`) is what still makes
    // sure only one of them is ever audibly playing at once.
    @StateObject private var appState: AppState
    @ObservedObject private var engine: PlaybackEngine
    @State private var isTargetedForDrop = false

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        engine = state.engine
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            if let tune = appState.tune {
                PartProgressView(
                    tune: appState.progressTune ?? tune,
                    currentTime: engine.currentTime,
                    tempo: engine.tempo,
                    onSeek: { engine.seek(to: $0) }
                )
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
        .navigationTitle(windowTitle)
        .background(dropHighlightOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
        .onDisappear {
            // Closing the window (the red button) tears down this view
            // without quitting the app — playback should stop right along
            // with it rather than keep running with no window to control it.
            engine.stop()
        }
        .onOpenURL { url in
            // Finder's "Open With"/double-click and the custom document-type
            // registrations in package_app.sh's Info.plist deliver the file
            // here — without this, Launch Services still launches/activates
            // the app and opens a window, but nothing ever reads the file.
            appState.open(url: url)
        }
        .focusedSceneObject(appState)
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

    // A native window/tab title is plain text — no way to place an actual
    // SF Symbol glyph in it — so a currently-playing tab is marked with a
    // speaker emoji prefix instead, the closest plain-text equivalent to
    // "speaker.wave.2". Only shown while actually playing (not paused or
    // stopped), so it reads as "this is the tab making sound right now."
    private var windowTitle: String {
        let title = appState.tune?.title ?? "PipePlayer"
        return engine.state == .playing ? "🔊 \(title)" : title
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
