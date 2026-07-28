import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the currently-loaded tune, the shared `PlaybackEngine`, and the
/// recent-files list — shared between `ContentView` and the File menu
/// commands (which live at the Scene level, outside the view hierarchy, so
/// they need a reference to the same state rather than view-local `@State`).
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var voices: [Voice] = []
    @Published var errorMessage: String?
    @Published private(set) var recentURLs: [URL] = []

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

    private let recentsDefaultsKey = "PipePlayer.recentFileURLs"
    private let maxRecents = 10

    init() {
        loadRecents()
        nowPlayingController = NowPlayingController(engine: engine)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = TuneFileLoader.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let loadedVoices = try TuneFileLoader.loadVoices(from: url)
            let alignedVoices = VoiceAligner.align(loadedVoices)
            voices = alignedVoices
            progressTune = alignedVoices.first.map { EmbellishmentExpander.expand(tune: $0.tune) }
            engine.load(voices: alignedVoices)
            addRecent(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeTune() {
        engine.stop()
        voices = []
        progressTune = nil
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
        guard let paths = UserDefaults.standard.array(forKey: recentsDefaultsKey) as? [String] else { return }
        recentURLs = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func saveRecents() {
        UserDefaults.standard.set(recentURLs.map(\.path), forKey: recentsDefaultsKey)
    }
}
