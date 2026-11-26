import Foundation

/// The Open Recent list, shared by every tab. Was a per-`AppState` copy
/// loaded once at init, so a file opened in one tab didn't show up in
/// another tab's menu until relaunch.
///
/// Stored as bookmarks rather than paths, same as each tab's own tune, so a
/// file moved or renamed since it was opened stays on the list.
@MainActor
final class RecentTunes: ObservableObject {
    static let shared = RecentTunes()

    @Published private(set) var urls: [URL] = []

    private let defaults: UserDefaults
    private let maxCount = 10
    static let bookmarksKey = "PipePlayer.recentFileBookmarks"
    /// Pre-bookmark versions stored plain paths here. Read once to migrate.
    static let legacyPathsKey = "PipePlayer.recentFileURLs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ url: URL) {
        var list = urls.filter { !$0.isSameFile(as: url) }
        list.insert(url, at: 0)
        if list.count > maxCount { list.removeLast(list.count - maxCount) }
        urls = list
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func load() {
        if let bookmarks = defaults.array(forKey: Self.bookmarksKey) as? [Data] {
            urls = bookmarks.compactMap { data in
                var isStale = false
                guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale),
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url
            }
        } else if let paths = defaults.array(forKey: Self.legacyPathsKey) as? [String] {
            urls = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            defaults.removeObject(forKey: Self.legacyPathsKey)
        }
        // Re-saving refreshes any stale bookmarks and drops dead entries.
        save()
    }

    private func save() {
        defaults.set(urls.compactMap { try? $0.bookmarkData() }, forKey: Self.bookmarksKey)
    }
}

extension URL {
    /// By file identity, not path string — a resolved bookmark can come
    /// back spelled differently (symlinks, case) than the URL it was made
    /// from.
    func isSameFile(as other: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let a = try? resourceValues(forKeys: key).fileResourceIdentifier,
           let b = try? other.resourceValues(forKeys: key).fileResourceIdentifier {
            return a.isEqual(b)
        }
        return resolvingSymlinksInPath().path == other.resolvingSymlinksInPath().path
    }
}
