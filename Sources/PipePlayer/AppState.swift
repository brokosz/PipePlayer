import Foundation
import AppKit
import UniformTypeIdentifiers

/// Files picked from the File menu while no window was open, waiting for
/// the window opened for them to claim one. SwiftUI's `openWindow(id:)`
/// can't hand a value to the new window directly (that would need a
/// value-typed `WindowGroup`), so the menu command parks the URL here and
/// the new window's `ContentView` takes it on appear.
@MainActor
final class PendingTuneOpens {
    static let shared = PendingTuneOpens()
    private var urls: [URL] = []

    func enqueue(_ url: URL) { urls.append(url) }

    func takeNext() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}

/// Owns the currently-loaded tune, the shared `PlaybackEngine`, and the
/// recent-files list — shared between `ContentView` and the File menu
/// commands (which live at the Scene level, outside the view hierarchy, so
/// they need a reference to the same state rather than view-local `@State`).
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var voices: [Voice] = []
    @Published var errorMessage: String?
    @Published private(set) var recentURLs: [URL] = []
    /// The file this window's tune came from — what `ContentView` persists
    /// so the tab can reopen it after a relaunch.
    @Published private(set) var currentURL: URL?

    /// The primary voice's tune — drives the window title. For a multi-voice
    /// MusicXML harmony arrangement this is the first `<part>` (conventionally
    /// the melody); every voice still contributes audio via `engine`,
    /// independent of what's shown here.
    var tune: Tune? { voices.first?.tune }

    /// The primary voice's tune with embellishments already expanded —
    /// what `PartProgressView` measures its part spans against. Grace notes
    /// add a small sliver of real playback time rather than borrowing it from
    /// the note they decorate (see `EmbellishmentExpander`), so a progress
    /// bar computed from *un*-expanded note durations would fall increasingly
    /// behind the real audio, finishing each part before it's actually done.
    /// `MIDIEventBuilder` expands internally too — this is computed once
    /// here (not per SwiftUI body re-render) so both sides agree on the same
    /// timeline without re-running the expansion dozens of times a second.
    @Published private(set) var progressTune: Tune?

    let engine = PlaybackEngine()
    // Retained here so its Combine subscriptions (which keep the media-key
    // now-playing info in sync with playback) stay alive for the app's
    // lifetime — see NowPlayingController.
    private var nowPlayingController: NowPlayingController?

    private static let recentsDefaultsKey = "PipePlayer.recentFileURLs"
    private let maxRecents = 10

    init() {
        loadRecents()
        nowPlayingController = NowPlayingController(engine: engine)
    }

    func presentOpenPanel() {
        guard let url = Self.chooseTuneFile() else { return }
        open(url: url)
    }

    /// Static so File → Open works with no window open at all — there's no
    /// AppState to call `presentOpenPanel` on until a window exists.
    static func chooseTuneFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = TuneFileLoader.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// `addToRecents: false` is for restoring a tab's tune on relaunch —
    /// reopening every restored tab shouldn't reshuffle Open Recent into
    /// whatever order the windows happened to come back in.
    func open(url: URL, addToRecents: Bool = true) {
        do {
            let loadedVoices = try TuneFileLoader.loadVoices(from: url)
            let alignedVoices = VoiceAligner.align(loadedVoices)
            voices = alignedVoices
            progressTune = alignedVoices.first.map { EmbellishmentExpander.expand(tune: $0.tune) }
            engine.load(voices: alignedVoices)
            currentURL = url
            if addToRecents { addRecent(url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeTune() {
        engine.stop()
        voices = []
        progressTune = nil
        currentURL = nil
    }

    // MARK: - Recents

    private func addRecent(_ url: URL) {
        var urls = recentURLs.filter { $0 != url }
        urls.insert(url, at: 0)
        if urls.count > maxRecents {
            urls.removeLast(urls.count - maxRecents)
        }
        recentURLs = urls
        saveRecents()
    }

    func clearRecents() {
        recentURLs = []
        saveRecents()
    }

    private func loadRecents() {
        recentURLs = Self.storedRecentURLs()
    }

    /// Read straight from defaults so Open Recent still works with no
    /// window (and so no AppState) open.
    static func storedRecentURLs() -> [URL] {
        guard let paths = UserDefaults.standard.array(forKey: recentsDefaultsKey) as? [String] else { return [] }
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clearStoredRecents() {
        UserDefaults.standard.removeObject(forKey: recentsDefaultsKey)
    }

    private func saveRecents() {
        UserDefaults.standard.set(recentURLs.map(\.path), forKey: Self.recentsDefaultsKey)
    }
}
