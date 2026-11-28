import Foundation

/// A set: tunes played straight through, each once, each at its own tempo
/// (a competition MSR, or three reels to hear how they sit together).
/// Saved as a `.pipeset` JSON file next to the tunes.
///
/// Each tune is stored by its path relative to the set file, so a folder
/// moved or copied with its set still opens; a bookmark is kept as a
/// fallback for a tune that moved on its own.
struct SetList: Codable, Equatable {
    var name: String
    var entries: [Entry]

    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var relativePath: String?
        var bookmark: Data?
        /// The tempo this tune plays at in the set; nil uses the file's.
        var tempo: Double?
    }

    static let fileExtension = "pipeset"

    mutating func append(_ url: URL, relativeTo setURL: URL?) {
        entries.append(Entry(
            relativePath: setURL.map { Self.relativePath(of: url, from: $0) },
            bookmark: try? url.bookmarkData()
        ))
    }

    /// The tune's file: its relative path when that file exists, else
    /// wherever its bookmark leads.
    func url(for entry: Entry, relativeTo setURL: URL?) -> URL? {
        if let setURL, let path = entry.relativePath {
            let candidate = URL(fileURLWithPath: path, relativeTo: setURL.deletingLastPathComponent()).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        guard let bookmark = entry.bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Recomputes every relative path for a set saved to `newSetURL` —
    /// an untitled set's first save, or Save As somewhere else.
    mutating func rebase(to newSetURL: URL, from oldSetURL: URL?) {
        for index in entries.indices {
            guard let url = url(for: entries[index], relativeTo: oldSetURL) else { continue }
            entries[index].relativePath = Self.relativePath(of: url, from: newSetURL)
        }
    }

    static func load(from url: URL) throws -> SetList {
        try JSONDecoder().decode(SetList.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// `file`'s path from the folder holding `setURL`, with `..` as needed.
    static func relativePath(of file: URL, from setURL: URL) -> String {
        let base = setURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let target = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < base.count, common < target.count, base[common] == target[common] { common += 1 }
        let ups = Array(repeating: "..", count: base.count - common)
        return (ups + target[common...]).joined(separator: "/")
    }
}
