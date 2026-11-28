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
        /// Harmony files played with this tune (band seconds).
        var harmonies: [FileRef] = []

        var ref: FileRef { FileRef(relativePath: relativePath, bookmark: bookmark) }

        init(id: UUID = UUID(), relativePath: String? = nil, bookmark: Data? = nil, tempo: Double? = nil, harmonies: [FileRef] = []) {
            self.id = id
            self.relativePath = relativePath
            self.bookmark = bookmark
            self.tempo = tempo
            self.harmonies = harmonies
        }

        // Sets saved before harmonies existed have no `harmonies` key.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath)
            bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
            tempo = try c.decodeIfPresent(Double.self, forKey: .tempo)
            harmonies = try c.decodeIfPresent([FileRef].self, forKey: .harmonies) ?? []
        }
    }

    /// A file the set points at: its path relative to the set file, and a
    /// bookmark as fallback.
    struct FileRef: Codable, Equatable {
        /// Stable across edits, so a harmony's voice (and its mute) keeps
        /// its identity when another harmony is removed.
        var id: UUID = UUID()
        var relativePath: String?
        var bookmark: Data?

        init(relativePath: String?, bookmark: Data?) {
            self.relativePath = relativePath
            self.bookmark = bookmark
        }

        init(_ url: URL, relativeTo setURL: URL?) {
            relativePath = setURL.map { SetList.relativePath(of: url, from: $0) }
            bookmark = try? url.bookmarkData()
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath)
            bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        }
    }

    static let fileExtension = "pipeset"

    mutating func append(_ url: URL, relativeTo setURL: URL?) {
        let ref = FileRef(url, relativeTo: setURL)
        entries.append(Entry(relativePath: ref.relativePath, bookmark: ref.bookmark))
    }

    mutating func addHarmony(_ url: URL, toEntry id: UUID, relativeTo setURL: URL?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var ref = FileRef(url, relativeTo: setURL)
        // The same file again replaces the earlier reference, keeping its id
        // (and so its mute), rather than doubling it.
        if let existing = entries[index].harmonies.firstIndex(where: {
            self.url(for: $0, relativeTo: setURL)?.isSameFile(as: url) ?? false
        }) {
            ref.id = entries[index].harmonies[existing].id
            entries[index].harmonies[existing] = ref
        } else {
            entries[index].harmonies.append(ref)
        }
    }

    mutating func removeHarmony(at harmonyIndex: Int, fromEntry id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].harmonies.indices.contains(harmonyIndex) else { return }
        entries[index].harmonies.remove(at: harmonyIndex)
    }

    /// The tune's file: its relative path when that file exists, else
    /// wherever its bookmark leads.
    func url(for entry: Entry, relativeTo setURL: URL?) -> URL? {
        url(for: entry.ref, relativeTo: setURL)
    }

    func url(for ref: FileRef, relativeTo setURL: URL?) -> URL? {
        if let setURL, let path = ref.relativePath {
            let candidate = URL(fileURLWithPath: path, relativeTo: setURL.deletingLastPathComponent()).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        guard let bookmark = ref.bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Recomputes every relative path for a set saved to `newSetURL` —
    /// an untitled set's first save, or Save As somewhere else.
    mutating func rebase(to newSetURL: URL, from oldSetURL: URL?) {
        for index in entries.indices {
            if let url = url(for: entries[index], relativeTo: oldSetURL) {
                entries[index].relativePath = Self.relativePath(of: url, from: newSetURL)
            }
            for h in entries[index].harmonies.indices {
                if let url = url(for: entries[index].harmonies[h], relativeTo: oldSetURL) {
                    entries[index].harmonies[h].relativePath = Self.relativePath(of: url, from: newSetURL)
                }
            }
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
