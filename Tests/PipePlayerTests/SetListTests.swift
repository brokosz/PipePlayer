import Testing
import Foundation
@testable import PipePlayer

struct SetListTests {

    /// A folder holding `set.pipeset`'s neighbours: `a.bww` and `sub/b.bww`.
    private func makeFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "a".write(to: dir.appendingPathComponent("a.bww"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("sub/b.bww"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func roundTripsThroughAFile() throws {
        let dir = try makeFolder()
        let setURL = dir.appendingPathComponent("set.pipeset")
        var set = SetList(name: "MSR", entries: [])
        set.append(dir.appendingPathComponent("a.bww"), relativeTo: setURL)
        set.entries[0].tempo = 80
        try set.write(to: setURL)
        #expect(try SetList.load(from: setURL) == set)
    }

    @Test func storesPathsRelativeToTheSetFile() throws {
        let dir = try makeFolder()
        var set = SetList(name: "S", entries: [])
        set.append(dir.appendingPathComponent("sub/b.bww"), relativeTo: dir.appendingPathComponent("set.pipeset"))
        #expect(set.entries[0].relativePath == "sub/b.bww")
    }

    @Test func resolvesAfterMovingTheFolder() throws {
        let dir = try makeFolder()
        var set = SetList(name: "S", entries: [])
        set.append(dir.appendingPathComponent("sub/b.bww"), relativeTo: dir.appendingPathComponent("set.pipeset"))
        let moved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: dir, to: moved)
        let url = set.url(for: set.entries[0], relativeTo: moved.appendingPathComponent("set.pipeset"))
        #expect(url?.standardizedFileURL.path == moved.appendingPathComponent("sub/b.bww").standardizedFileURL.path)
    }

    @Test func fallsBackToTheBookmarkWhenThePathIsGone() throws {
        let dir = try makeFolder()
        let setURL = dir.appendingPathComponent("set.pipeset")
        var set = SetList(name: "S", entries: [])
        set.append(dir.appendingPathComponent("a.bww"), relativeTo: setURL)
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pipeset")
        let url = set.url(for: set.entries[0], relativeTo: elsewhere)
        #expect(url?.lastPathComponent == "a.bww")
    }

    @Test func rebaseRewritesRelativePaths() throws {
        let dir = try makeFolder()
        var set = SetList(name: "S", entries: [])
        set.append(dir.appendingPathComponent("sub/b.bww"), relativeTo: nil)
        set.rebase(to: dir.appendingPathComponent("set.pipeset"), from: nil)
        #expect(set.entries[0].relativePath == "sub/b.bww")
        set.rebase(to: dir.appendingPathComponent("sub/set.pipeset"), from: dir.appendingPathComponent("set.pipeset"))
        #expect(set.entries[0].relativePath == "b.bww")
    }
}
