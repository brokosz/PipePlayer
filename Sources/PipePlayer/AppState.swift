import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the currently-loaded tune, the shared `PlaybackEngine`, and the
/// recent-files list — shared between `ContentView` and the File menu
/// commands (which live at the Scene level, outside the view hierarchy, so
/// they need a reference to the same state rather than view-local `@State`).
@MainActor
final class AppState: ObservableObject {
    @Published var tune: Tune?
    @Published var errorMessage: String?
    @Published private(set) var recentURLs: [URL] = []

    let engine = PlaybackEngine()

    private let recentsDefaultsKey = "PipePlayer.recentFileURLs"
    private let maxRecents = 10

    init() {
        loadRecents()
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
            let loaded = try TuneFileLoader.load(from: url)
            tune = loaded
            engine.load(loaded)
            addRecent(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeTune() {
        engine.stop()
        tune = nil
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
