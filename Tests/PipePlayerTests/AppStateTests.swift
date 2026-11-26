import Testing
import Foundation
@testable import PipePlayer

@MainActor
struct AppStateTests {

    static func writeTempTune(_ name: String = "Test") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bww")
        try """
        Bagpipe Music Writer Gold:1.0

        "\(name)",(T,L,10,10,Times New Roman,14,0)
        & sharpf sharpc 2_4 I!''
        ! LA_8 B_8 ''!I
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A recents store on its own defaults suite, so tests never touch the
    /// real Open Recent list.
    static func scratchRecents() -> RecentTunes {
        let suite = "PipePlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return RecentTunes(defaults: defaults)
    }

    @Test func openRecordsTheFileAndCloseClearsIt() throws {
        let url = try Self.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState(recents: Self.scratchRecents())

        state.open(url: url)
        #expect(state.currentURL == url)
        #expect(state.tune != nil)
        #expect(state.recents.urls == [url])

        state.closeTune()
        #expect(state.currentURL == nil)
    }

    @Test func restoringATabDoesNotReshuffleRecents() throws {
        let url = try Self.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState(recents: Self.scratchRecents())

        state.open(url: url, addToRecents: false)
        #expect(state.recents.urls.isEmpty)
    }

    @Test func tempoOverrideIsNilAtTheFilesOwnTempo() throws {
        let url = try Self.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState(recents: Self.scratchRecents())
        state.open(url: url, addToRecents: false)

        #expect(state.tempoOverride == nil)
        state.engine.tempo = 61
        #expect(state.tempoOverride == 61)
    }

    @Test func applyingSavedSettingsRestoresTempoAndIgnoresUnknownVoices() throws {
        let url = try Self.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = AppState(recents: Self.scratchRecents())
        state.open(url: url, addToRecents: false)

        state.applyPlaybackSettings(tempoOverride: 70, mutedVoiceIDs: ["melody", "gone"])
        #expect(state.engine.tempo == 70)
        #expect(state.engine.mutedVoiceIDs == ["melody"])

        state.applyPlaybackSettings(tempoOverride: nil, mutedVoiceIDs: [])
        #expect(state.engine.tempo == state.tune?.tempo)
        #expect(state.engine.mutedVoiceIDs.isEmpty)
    }

    @Test func progressTimelineMatchesPlaybackForAStrathspey() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".abc")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        X:1
        T:Pointed
        R:strathspey
        M:4/4
        L:1/8
        K:HP
        A>B c<d e>f g<a|
        """.write(to: url, atomically: true, encoding: .utf8)
        let state = AppState(recents: Self.scratchRecents())
        state.open(url: url, addToRecents: false)

        let tune = try #require(state.tune)
        let expected = EmbellishmentExpander.expand(tune: PerformanceStyle.apply(to: tune))
        #expect(state.progressTune == expected)
        #expect(state.progressTune != EmbellishmentExpander.expand(tune: tune))
    }
}

@MainActor
struct RecentTunesTests {

    @Test func addMovesAnExistingFileToTheTopWithoutDuplicating() throws {
        let a = try AppStateTests.writeTempTune("A")
        let b = try AppStateTests.writeTempTune("B")
        defer { [a, b].forEach { try? FileManager.default.removeItem(at: $0) } }
        let recents = AppStateTests.scratchRecents()

        recents.add(a)
        recents.add(b)
        recents.add(a)
        #expect(recents.urls == [a, b])
    }

    @Test func survivesAFileBeingRenamed() throws {
        let suite = "PipePlayerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try AppStateTests.writeTempTune()
        let renamed = original.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".bww")
        defer { try? FileManager.default.removeItem(at: renamed) }

        RecentTunes(defaults: defaults).add(original)
        try FileManager.default.moveItem(at: original, to: renamed)

        let reloaded = RecentTunes(defaults: defaults)
        #expect(reloaded.urls.count == 1)
        #expect(reloaded.urls.first?.isSameFile(as: renamed) == true)
    }

    @Test func migratesLegacyPathListAndDropsMissingFiles() throws {
        let suite = "PipePlayerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try AppStateTests.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        defaults.set([url.path, "/nonexistent/tune.bww"], forKey: RecentTunes.legacyPathsKey)

        let recents = RecentTunes(defaults: defaults)
        #expect(recents.urls == [url])
        #expect(defaults.object(forKey: RecentTunes.legacyPathsKey) == nil)
        #expect((defaults.array(forKey: RecentTunes.bookmarksKey) as? [Data])?.count == 1)
    }
}

@MainActor
struct TuneOpenerTests {

    @Test func loadsIntoAnEmptyTab() throws {
        let url = try AppStateTests.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let tab = AppState(recents: AppStateTests.scratchRecents())
        var newTabs = 0

        TuneOpener.open(url, from: tab) { newTabs += 1 }
        #expect(tab.currentURL == url)
        #expect(newTabs == 0)
    }

    @Test func neverReplacesALoadedTune() throws {
        let a = try AppStateTests.writeTempTune("A")
        let b = try AppStateTests.writeTempTune("B")
        defer { [a, b].forEach { try? FileManager.default.removeItem(at: $0) } }
        let tab = AppState(recents: AppStateTests.scratchRecents())
        tab.open(url: a)
        var newTabs = 0

        TuneOpener.open(b, from: tab) { newTabs += 1 }
        #expect(tab.currentURL == a)
        #expect(newTabs == 1)
        #expect(PendingTuneOpens.shared.takeNext() == b)
    }

    @Test func reusesTheTabAlreadyShowingTheFile() throws {
        let url = try AppStateTests.writeTempTune()
        defer { try? FileManager.default.removeItem(at: url) }
        let showing = AppState(recents: AppStateTests.scratchRecents())
        showing.open(url: url)
        let empty = AppState(recents: AppStateTests.scratchRecents())
        var newTabs = 0

        TuneOpener.open(url, from: empty) { newTabs += 1 }
        #expect(empty.currentURL == nil)
        #expect(newTabs == 0)
    }
}
