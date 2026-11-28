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
    /// Which zone a drag over the window is in (see `DropZone`).
    @State private var dropZone: DropZone = .open
    @State private var windowSize: CGSize = .zero
    // Per-window, saved and restored by SwiftUI alongside the window itself
    // — the same mechanism that already brings tabs back on relaunch.
    // Without it, every restored tab came back with a fresh, empty AppState.
    // A bookmark rather than a path, so a tune moved or renamed in the
    // meantime still reopens.
    @SceneStorage("PipePlayer.tuneBookmark") private var tuneBookmark: Data?
    // Tempo (0 = the file's own) and muted voice IDs, newline-joined —
    // SceneStorage only takes plain scalar types.
    @SceneStorage("PipePlayer.tempoOverride") private var savedTempo: Double = 0
    @SceneStorage("PipePlayer.mutedVoices") private var savedMutes: String = ""
    // Bookmarks of files added as harmony, as a property-list [Data].
    @SceneStorage("PipePlayer.harmonyBookmarks") private var savedHarmonies: Data = Data()
    // An untitled set's contents (JSON) — it has no file to bookmark yet.
    @SceneStorage("PipePlayer.untitledSet") private var savedUntitledSet: Data = Data()
    @Environment(\.openWindow) private var openWindow

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        engine = state.engine
    }

    var body: some View {
        // Fixed pieces are pinned to their natural height (`natural()`), so
        // the stack's minimum is exactly what it needs and the window can't
        // clip them; the set list and the progress bar take any extra.
        VStack(spacing: 16) {
            header.natural()
            Divider()
            if appState.isSet {
                SetListView(appState: appState, engine: engine)
                if !engine.segments.isEmpty {
                    PartProgressView(
                        timeline: engine.partTimeline,
                        currentTime: engine.currentTime,
                        loopedPartIndex: engine.loopedPartIndex,
                        tuneTitles: appState.segmentTitles,
                        onSeek: { engine.seek(to: $0) }
                    )
                    if engine.currentVoices.count > 1 {
                        voiceRow
                    }
                    TransportControlsView(engine: engine).natural()
                }
            } else if appState.tune != nil {
                PartProgressView(
                    timeline: engine.partTimeline,
                    currentTime: engine.currentTime,
                    loopedPartIndex: engine.loopedPartIndex,
                    onSeek: { engine.seek(to: $0) }
                )
                if engine.currentVoices.count > 1 {
                    voiceRow
                }
                TransportControlsView(engine: engine).natural()
                Spacer(minLength: 0)
            } else {
                emptyState
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 460, maxHeight: .infinity, alignment: .top)
        .navigationTitle(windowTitle)
        .background(dropHighlightOverlay)
        .background(WindowAccessor { appState.window = $0 })
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { windowSize = geo.size }
                .onChange(of: geo.size) { windowSize = $0 }
        })
        .onDrop(of: [.fileURL], delegate: TuneDropDelegate(
            isTargeted: $isTargetedForDrop,
            zone: $dropZone,
            hasZones: canAddHarmony,
            isSet: appState.isSet,
            size: windowSize,
            perform: handleDrop
        ))
        .onDisappear {
            // Closing the window (the red button) tears down this view
            // without quitting the app — playback should stop right along
            // with it rather than keep running with no window to control it.
            engine.stop()
            OpenTabs.shared.unregister(appState)
        }
        .onAppear {
            // A window opened from File → Open with nothing else open is
            // here to show that file; otherwise it may be a restored tab.
            if let url = PendingTuneOpens.shared.takeNext() {
                appState.open(url: url)
            } else if PendingTuneOpens.shared.takeNewSet() {
                appState.newSet()
            } else {
                restoreTuneIfNeeded()
            }
        }
        .onChange(of: tuneBookmark) { _ in
            // SwiftUI delivers a restored tab's scene storage a beat *after*
            // `onAppear` (observed ~200ms on relaunch), so the check there
            // alone always saw nil. This is where restoration actually lands.
            restoreTuneIfNeeded()
        }
        .onChange(of: savedTempo) { _ in applySavedPlaybackSettings() }
        .onChange(of: savedMutes) { _ in applySavedPlaybackSettings() }
        .onChange(of: appState.currentURL) { url in
            tuneBookmark = url.flatMap { try? $0.bookmarkData() }
            if url == nil {
                savedTempo = 0
                savedMutes = ""
            }
        }
        .onChange(of: engine.tempo) { _ in savePlaybackSettings() }
        .onChange(of: engine.mutedVoiceIDs) { _ in savePlaybackSettings() }
        .onChange(of: appState.setList) { set in
            // Kept only while the set is untitled; once saved, the tune
            // bookmark (the set file) brings it back.
            let untitled = appState.currentURL == nil ? set : nil
            savedUntitledSet = untitled.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        }
        .onChange(of: savedUntitledSet) { _ in restoreUntitledSetIfNeeded() }
        .onChange(of: appState.harmonyURLs) { urls in
            let bookmarks = urls.compactMap { try? $0.bookmarkData() }
            savedHarmonies = (try? PropertyListEncoder().encode(bookmarks)) ?? Data()
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
    private var displayTitle: String {
        appState.setList?.name ?? appState.tune?.title ?? "PipePlayer"
    }

    /// In a set, the tune at the playhead.
    private var setTuneTitle: String? {
        guard appState.isSet, !engine.segments.isEmpty,
              appState.segmentTitles.indices.contains(engine.currentSegmentIndex) else { return nil }
        return appState.segmentTitles[engine.currentSegmentIndex]
    }

    private var windowTitle: String {
        let title = displayTitle
        return engine.state == .playing ? "🔊 \(title)" : title
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(displayTitle)
                    .font(.title2).bold()
                if let setTuneTitle {
                    Text(setTuneTitle).foregroundStyle(.secondary)
                } else if let composer = appState.tune?.composer, !composer.isEmpty {
                    Text(composer).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Open…") {
                AppState.chooseTuneFiles().forEach(openTune)
            }
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
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var voiceRow: some View {
        VoiceMuteControlsView(
            engine: engine,
            isHarmony: { appState.isHarmony($0) },
            onRemoveHarmony: { appState.removeHarmony(voiceID: $0) }
        )
        .natural()
    }

    /// A tune is open, or a set with a tune to attach the harmony to.
    private var canAddHarmony: Bool {
        appState.tune != nil || (appState.isSet && !engine.segments.isEmpty)
    }

    @ViewBuilder
    private var dropHighlightOverlay: some View {
        if isTargetedForDrop {
            if !canAddHarmony {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
            } else if appState.isSet {
                HStack(spacing: 8) {
                    dropHalf("Add to Set", systemImage: "text.badge.plus", isActive: dropZone == .addToSet)
                    dropHalf("Add as Harmony", systemImage: "plus.square.on.square", isActive: dropZone == .harmony)
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        dropHalf("Open", systemImage: "doc", isActive: dropZone == .open)
                        dropHalf("Add as Harmony", systemImage: "plus.square.on.square", isActive: dropZone == .harmony)
                    }
                    dropHalf("Start a Set with Both", systemImage: "text.badge.plus", isActive: dropZone == .startSet)
                }
            }
        }
    }

    private func dropHalf(_ title: String, systemImage: String, isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.accentColor.opacity(isActive ? 0.15 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(isActive ? 1 : 0.35), lineWidth: isActive ? 3 : 1.5)
            )
            .overlay(
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            )
    }

    private func openTune(_ url: URL) {
        TuneOpener.open(url, from: appState) { openWindow(id: "main") }
    }

    /// A bookmark that no longer resolves means the file is gone — the tab
    /// just comes back empty rather than greeting a relaunch with an error.
    /// One that resolves but fails to parse still alerts, since that's a
    /// real problem with the file, not a missing one. A stale bookmark gets
    /// refreshed automatically once `open` updates `currentURL`.
    ///
    /// If a file already landed in this tab before the restored value
    /// arrived (a Finder double-click that launches the app races the
    /// restore), the tab keeps that file and its restored tune moves to a
    /// tab of its own rather than being dropped.
    private func restoreTuneIfNeeded() {
        guard let bookmark = tuneBookmark else {
            restoreUntitledSetIfNeeded()
            return
        }
        var isStale = false
        let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
        if let current = appState.currentURL {
            guard let url, !url.isSameFile(as: current) else {
                if url == nil { tuneBookmark = try? current.bookmarkData() }
                return
            }
            tuneBookmark = try? current.bookmarkData()
            if OpenTabs.shared.tab(showing: url) == nil {
                PendingTuneOpens.shared.enqueue(url)
                openWindow(id: "main")
            }
            return
        }
        guard appState.tune == nil else { return }
        guard let url else {
            tuneBookmark = nil
            return
        }
        appState.open(url: url, addToRecents: false)
        restoreHarmonies()
        applySavedPlaybackSettings()
    }

    private func restoreUntitledSetIfNeeded() {
        guard appState.isEmptyTab, tuneBookmark == nil, !savedUntitledSet.isEmpty,
              let set = try? JSONDecoder().decode(SetList.self, from: savedUntitledSet) else { return }
        appState.restoreUntitledSet(set)
    }

    /// Re-adds the tab's harmony files; ones that no longer resolve are
    /// skipped quietly, like a missing tune.
    private func restoreHarmonies() {
        guard let bookmarks = try? PropertyListDecoder().decode([Data].self, from: savedHarmonies) else { return }
        let urls = bookmarks.compactMap { data -> URL? in
            var isStale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        }
        if !urls.isEmpty { appState.addHarmony(urls: urls) }
    }

    private func applySavedPlaybackSettings() {
        appState.applyPlaybackSettings(
            tempoOverride: savedTempo > 0 ? savedTempo : nil,
            mutedVoiceIDs: Set(savedMutes.split(separator: "\n").map(String.init))
        )
    }

    private func savePlaybackSettings() {
        guard appState.tune != nil else { return }
        let tempo = appState.tempoOverride ?? 0
        let mutes = engine.mutedVoiceIDs.sorted().joined(separator: "\n")
        if savedTempo != tempo { savedTempo = tempo }
        if savedMutes != mutes { savedMutes = mutes }
    }

    private func handleDrop(_ providers: [NSItemProvider], zone: DropZone) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    let isSetFile = url.pathExtension.lowercased() == SetList.fileExtension
                    switch zone {
                    case .harmony where !isSetFile:
                        appState.addHarmony(urls: [url])
                    case .startSet where !isSetFile:
                        // Several files: the first starts the set, the rest join it.
                        if appState.isSet { appState.addToSet(urls: [url]) } else { appState.makeSet(adding: [url]) }
                    case .addToSet where !isSetFile:
                        appState.addToSet(urls: [url])
                    default:
                        openTune(url)
                    }
                }
            }
        }
        return true
    }
}

/// Where a file dropped on the window goes. With a tune open: top left
/// opens it, top right adds it as harmony, the bottom starts a set with both
/// tunes. In a set: left adds it to the set, right adds it as harmony to the
/// tune at the playhead. Kept off the view so it can be tested.
enum DropZone: Equatable {
    case open, harmony, startSet, addToSet

    static func at(_ point: CGPoint, in size: CGSize, isSet: Bool) -> DropZone {
        let right = point.x > size.width / 2
        if isSet { return right ? .harmony : .addToSet }
        if point.y > size.height / 2 { return .startSet }
        return right ? .harmony : .open
    }
}

/// Tracks which zone a drag is over (`DropZone`).
private struct TuneDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    @Binding var zone: DropZone
    /// False when there's nothing to add a harmony to: the whole window
    /// then opens the file (or adds it to an empty set).
    let hasZones: Bool
    let isSet: Bool
    let size: CGSize
    let perform: ([NSItemProvider], DropZone) -> Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        update(info)
        return perform(info.itemProviders(for: [.fileURL]), zone)
    }

    private func update(_ info: DropInfo) {
        zone = hasZones ? DropZone.at(info.location, in: size, isSet: isSet) : (isSet ? .addToSet : .open)
    }
}


/// Hands back the `NSWindow` hosting a SwiftUI view — SwiftUI has no
/// public way to reach it, and `TuneOpener` needs it to bring an
/// already-open tab forward.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

private extension View {
    /// Never shorter or taller than the view's natural height. The window's
    /// minimum size is the sum of its pieces' minimums; without this some
    /// controls reported less than they draw, and a short window (or the
    /// tab bar appearing) clipped the heading and bottom controls.
    func natural() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}

