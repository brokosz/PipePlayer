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
        #expect(state.engine.partTimeline == PlayOrder.timeline(of: expected, tempo: state.engine.tempo))
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

    /// A closed window's tab can outlive the window in memory; it must not
    /// be reused for a file opened from Finder, or the file goes nowhere.
    @Test func aClosedTabIsntReused() throws {
        let url = try AppStateTests.writeTempTune()
        let closed = AppState(recents: AppStateTests.scratchRecents())
        closed.open(url: url, addToRecents: false)
        let empty = AppState(recents: AppStateTests.scratchRecents())
        OpenTabs.shared.unregister(closed)
        OpenTabs.shared.unregister(empty)
        #expect(OpenTabs.shared.tab(showing: url) == nil)
        #expect(OpenTabs.shared.firstEmptyTab !== empty)
    }

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

@MainActor
struct HarmonyTests {

    /// A tune file with a chosen name, in its own folder.
    static func writeTune(named fileName: String, body: String = "! LA_8 B_8 ''!I") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try """
        Bagpipe Music Writer Gold:1.0

        "Tune",(T,L,10,10,Times New Roman,14,0)
        & sharpf sharpc 2_4 I!''
        \(body)
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func stateWithMelody() throws -> AppState {
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.open(url: try Self.writeTune(named: "Tune.bww"))
        return state
    }

    @Test func addHarmonyAppendsAVoiceNamedAfterTheFile() throws {
        let state = try stateWithMelody()
        state.addHarmony(urls: [try Self.writeTune(named: "Tune - Seconds.bww", body: "! C_8 D_8 ''!I")])
        #expect(state.voices.count == 2)
        #expect(state.engine.voices.count == 2)
        #expect(state.voices[1].name == "Tune - Seconds")
        #expect(state.isHarmony(state.voices[1].id))
        #expect(!state.isHarmony(state.voices[0].id))
    }

    @Test func addingTheSameFileTwiceReplacesIt() throws {
        let state = try stateWithMelody()
        let seconds = try Self.writeTune(named: "Seconds.bww")
        state.addHarmony(urls: [seconds])
        state.addHarmony(urls: [seconds])
        #expect(state.voices.count == 2)
        #expect(state.harmonyURLs.count == 1)
    }

    @Test func addHarmonyKeepsTempoAndMutes() throws {
        let state = try stateWithMelody()
        state.engine.tempo = 70
        state.engine.setVoiceMuted(id: state.voices[0].id, muted: true)
        state.addHarmony(urls: [try Self.writeTune(named: "Seconds.bww")])
        #expect(state.engine.tempo == 70)
        #expect(state.engine.mutedVoiceIDs.contains(state.voices[0].id))
    }

    @Test func removingTheLastHarmonyUnmutesTheMelody() throws {
        let state = try stateWithMelody()
        state.addHarmony(urls: [try Self.writeTune(named: "Seconds.bww")])
        state.engine.setVoiceMuted(id: state.voices[0].id, muted: true)
        state.removeHarmony(voiceID: state.voices[1].id)
        #expect(state.engine.mutedVoiceIDs.isEmpty)
    }

    @Test func removeHarmonyRemovesItsVoices() throws {
        let state = try stateWithMelody()
        state.addHarmony(urls: [try Self.writeTune(named: "Seconds.bww")])
        state.removeHarmony(voiceID: state.voices[1].id)
        #expect(state.voices.count == 1)
        #expect(state.harmonyURLs.isEmpty)
    }

    @Test func openingAnotherTuneClearsHarmonies() throws {
        let state = try stateWithMelody()
        state.addHarmony(urls: [try Self.writeTune(named: "Seconds.bww")])
        state.open(url: try Self.writeTune(named: "Other.bww"))
        #expect(state.voices.count == 1)
        #expect(state.harmonyURLs.isEmpty)
    }

    @Test func aHarmonyThatFailsToParseLeavesVoicesAlone() throws {
        let state = try stateWithMelody()
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "nope".write(to: bad, atomically: true, encoding: .utf8)
        state.addHarmony(urls: [bad])
        #expect(state.errorMessage != nil)
        #expect(state.voices.count == 1)
        #expect(state.harmonyURLs.isEmpty)
    }
}

@MainActor
struct SetModeTests {

    /// Two tunes side by side in a fresh folder.
    private func folderWithTunes() throws -> (dir: URL, a: URL, b: URL) {
        let a = try HarmonyTests.writeTune(named: "A.bww")
        let dir = a.deletingLastPathComponent()
        let b = dir.appendingPathComponent("B.bww")
        try FileManager.default.copyItem(at: a, to: b)
        return (dir, a, b)
    }

    private func newState() -> AppState { AppState(recents: AppStateTests.scratchRecents()) }

    @Test func newSetIsEmptyAndUntitled() {
        let state = newState()
        state.newSet()
        #expect(state.isSet)
        #expect(state.setList?.entries.isEmpty == true)
        #expect(state.setList?.name == "Untitled Set")
        #expect(state.currentURL == nil)
        #expect(state.engine.duration == 0)
    }

    @Test func addingTunesBuildsOneSegmentEach() throws {
        let (_, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b])
        #expect(state.engine.segments.count == 2)
        #expect(state.segmentTitles.count == 2)
    }

    @Test func aMissingTuneIsSkippedAndExplained() throws {
        let (dir, a, _) = try folderWithTunes()
        let state = newState()
        state.newSet()
        let gone = dir.appendingPathComponent("Gone.bww")
        try FileManager.default.copyItem(at: a, to: gone)
        state.addToSet(urls: [a, gone])
        try FileManager.default.removeItem(at: gone)
        state.addToSet(urls: [])
        let goneID = try #require(state.setList?.entries.last?.id)
        #expect(state.entryProblems[goneID] != nil)
        #expect(state.engine.segments.count == 1)
    }

    @Test func editsSaveToTheFile() throws {
        let (dir, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a])
        let setURL = dir.appendingPathComponent("MSR.pipeset")
        try state.saveSet(to: setURL)
        #expect(state.currentURL == setURL)
        #expect(state.setList?.name == "MSR")
        state.addToSet(urls: [b])
        #expect(try SetList.load(from: setURL).entries.count == 2)
    }

    @Test func tempoChangesAreRememberedPerTune() throws {
        let (dir, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b])
        let setURL = dir.appendingPathComponent("S.pipeset")
        try state.saveSet(to: setURL)
        state.engine.seek(to: state.engine.segmentStarts[1] + 0.1)
        state.engine.tempo = 70
        let saved = try SetList.load(from: setURL)
        #expect(saved.entries[1].tempo == 70)
        #expect(saved.entries[0].tempo == nil)
    }

    @Test func removingThePlayingTuneGoesBackToTheStart() throws {
        let (_, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b])
        state.engine.seek(to: state.engine.segmentStarts[1] + 0.1)
        state.removeFromSet(id: state.setList!.entries[1].id)
        #expect(state.engine.currentTime == 0)
        #expect(state.engine.segments.count == 1)
    }

    @Test func removingThePlayingTuneMovesOnToTheNext() throws {
        let (dir, a, b) = try folderWithTunes()
        let c = dir.appendingPathComponent("C.bww")
        try FileManager.default.copyItem(at: a, to: c)
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b, c])
        state.engine.seek(to: state.engine.segmentStarts[1] + 0.1)
        state.removeFromSet(id: state.setList!.entries[1].id)
        #expect(state.engine.segments.count == 2)
        #expect(state.engine.currentTime == state.engine.segmentStarts[1])
    }

    @Test func removingAnEarlierTuneKeepsThePlace() throws {
        let (_, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b])
        state.engine.seek(to: state.engine.segmentStarts[1] + 0.1)
        state.removeFromSet(id: state.setList!.entries[0].id)
        #expect(abs(state.engine.currentTime - 0.1) < 0.0001)
    }

    @Test func removingTheLastTuneLeavesAnEmptySet() throws {
        let (_, a, _) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a])
        state.removeFromSet(id: state.setList!.entries[0].id)
        #expect(state.isSet)
        #expect(state.engine.duration == 0)
    }

    @Test func movingEntriesReordersSegments() throws {
        let (_, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a, b])
        let first = state.setList!.entries[0].id
        state.moveSetEntries(from: IndexSet(integer: 0), to: 2)
        #expect(state.setList!.entries[1].id == first)
    }

    @Test func openingAPipesetLoadsTheSet() throws {
        let (dir, a, b) = try folderWithTunes()
        let setURL = dir.appendingPathComponent("S.pipeset")
        var set = SetList(name: "S", entries: [])
        set.append(a, relativeTo: setURL)
        set.append(b, relativeTo: setURL)
        try set.write(to: setURL)
        let state = newState()
        state.open(url: setURL)
        #expect(state.isSet)
        #expect(state.engine.segments.count == 2)
        #expect(state.currentURL == setURL)
    }

    @Test func aTuneOpenedFromAnEmptySetTabGetsItsOwnTab() throws {
        let (_, a, _) = try folderWithTunes()
        let state = newState()
        state.newSet()
        var openedNewTab = false
        TuneOpener.open(a, from: state) { openedNewTab = true }
        #expect(openedNewTab)
        #expect(state.isSet)
        _ = PendingTuneOpens.shared.takeNext()
    }

    @Test func harmonyIsOffInASet() throws {
        let (_, a, b) = try folderWithTunes()
        let state = newState()
        state.newSet()
        state.addToSet(urls: [a])
        state.addHarmony(urls: [b])
        #expect(state.harmonyURLs.isEmpty)
    }
}

@MainActor
struct SetHarmonyTests {

    /// A.bww, B.bww and Seconds.bww side by side.
    private func folder() throws -> (dir: URL, a: URL, b: URL, seconds: URL) {
        let a = try HarmonyTests.writeTune(named: "A.bww")
        let dir = a.deletingLastPathComponent()
        let b = dir.appendingPathComponent("B.bww")
        let seconds = dir.appendingPathComponent("Seconds.bww")
        try FileManager.default.copyItem(at: a, to: b)
        try FileManager.default.copyItem(at: a, to: seconds)
        return (dir, a, b, seconds)
    }

    private func savedSet(_ f: (dir: URL, a: URL, b: URL, seconds: URL)) throws -> (AppState, URL) {
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.newSet()
        state.addToSet(urls: [f.a, f.b])
        let setURL = f.dir.appendingPathComponent("S.pipeset")
        try state.saveSet(to: setURL)
        return (state, setURL)
    }

    @Test func addingHarmonyInASetAttachesToTheTuneAtThePlayhead() throws {
        let f = try folder()
        let (state, _) = try savedSet(f)
        state.engine.seek(to: state.engine.segmentStarts[1] + 0.1)
        state.addHarmony(urls: [f.seconds])
        #expect(state.setList!.entries[0].harmonies.isEmpty)
        #expect(state.setList!.entries[1].harmonies.count == 1)
        #expect(state.engine.segments[1].voices.count == 2)
        #expect(state.harmonyNames(ofEntry: state.setList!.entries[1].id) == ["Seconds"])
    }

    @Test func setHarmoniesAreSavedAndReloaded() throws {
        let f = try folder()
        let (state, setURL) = try savedSet(f)
        state.addHarmony(urls: [f.seconds], toEntry: state.setList!.entries[0].id)
        let reopened = AppState(recents: AppStateTests.scratchRecents())
        reopened.open(url: setURL)
        #expect(reopened.engine.segments[0].voices.count == 2)
        #expect(reopened.isHarmony(reopened.engine.segments[0].voices[1].id))
    }

    @Test func removingASetHarmonyRemovesItFromTheFile() throws {
        let f = try folder()
        let (state, setURL) = try savedSet(f)
        state.addHarmony(urls: [f.seconds], toEntry: state.setList!.entries[0].id)
        state.removeHarmony(voiceID: state.engine.segments[0].voices[1].id)
        #expect(state.engine.segments[0].voices.count == 1)
        #expect(try SetList.load(from: setURL).entries[0].harmonies.isEmpty)
    }

    @Test func aMissingHarmonyDoesntStopTheTune() throws {
        let f = try folder()
        let (state, setURL) = try savedSet(f)
        state.addHarmony(urls: [f.seconds], toEntry: state.setList!.entries[0].id)
        try FileManager.default.removeItem(at: f.seconds)
        let reopened = AppState(recents: AppStateTests.scratchRecents())
        reopened.open(url: setURL)
        #expect(reopened.engine.segments.count == 2)
        #expect(reopened.engine.segments[0].voices.count == 1)
        #expect(reopened.entryProblems.isEmpty)
    }

    @Test func mutesSurviveASetReload() throws {
        let f = try folder()
        let (state, _) = try savedSet(f)
        state.addHarmony(urls: [f.seconds], toEntry: state.setList!.entries[0].id)
        let harmonyID = state.engine.segments[0].voices[1].id
        state.engine.setVoiceMuted(id: harmonyID, muted: true)
        state.addToSet(urls: [f.a])
        #expect(state.engine.mutedVoiceIDs.contains(harmonyID))
    }

    @Test func saveTuneAsSetKeepsItsHarmonies() throws {
        let f = try folder()
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.open(url: f.a)
        state.addHarmony(urls: [f.seconds])
        let setURL = f.dir.appendingPathComponent("Pairing.pipeset")
        try state.saveTuneAsSet(to: setURL)
        #expect(state.isSet)
        #expect(state.currentURL == setURL)
        let saved = try SetList.load(from: setURL)
        #expect(saved.entries.count == 1)
        #expect(saved.entries[0].relativePath == "A.bww")
        #expect(saved.entries[0].harmonies.map(\.relativePath) == ["Seconds.bww"])
        #expect(state.engine.segments[0].voices.count == 2)
    }
}

@MainActor
struct SetHarmonyEditTests {

    private func setWithTwoHarmonies() throws -> (AppState, UUID) {
        let a = try HarmonyTests.writeTune(named: "Tune.bww")
        let dir = a.deletingLastPathComponent()
        let first = dir.appendingPathComponent("First.bww")
        let second = dir.appendingPathComponent("Second.bww")
        try FileManager.default.copyItem(at: a, to: first)
        try FileManager.default.copyItem(at: a, to: second)
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.newSet()
        state.addToSet(urls: [a])
        let entry = state.setList!.entries[0].id
        state.addHarmony(urls: [first, second], toEntry: entry)
        try state.saveSet(to: dir.appendingPathComponent("S.pipeset"))
        return (state, entry)
    }

    private func voiceID(_ state: AppState, named name: String) -> String? {
        state.engine.segments[0].voices.first { $0.name == name }?.id
    }

    @Test func aMuteStaysWithItsHarmonyWhenAnotherIsRemoved() throws {
        let (state, _) = try setWithTwoHarmonies()
        state.engine.setVoiceMuted(id: try #require(voiceID(state, named: "Second")), muted: true)
        state.removeHarmony(voiceID: try #require(voiceID(state, named: "First")))
        let second = try #require(voiceID(state, named: "Second"))
        #expect(state.engine.mutedVoiceIDs == [second])
    }

    @Test func removingTheLastSetHarmonyUnmutesTheMelody() throws {
        let (state, entry) = try setWithTwoHarmonies()
        state.engine.setVoiceMuted(id: state.engine.segments[0].voices[0].id, muted: true)
        state.removeHarmony(at: 1, fromEntry: entry)
        state.removeHarmony(at: 0, fromEntry: entry)
        #expect(state.engine.mutedVoiceIDs.isEmpty)
    }

    @Test func aMissingHarmonyCanBeRemoved() throws {
        let (state, entry) = try setWithTwoHarmonies()
        state.removeHarmony(at: 0, fromEntry: entry)
        #expect(state.harmonyNames(ofEntry: entry) == ["Second"])
        #expect(try SetList.load(from: state.currentURL!).entries[0].harmonies.count == 1)
    }

    @Test func addingTheSameHarmonyTwiceInASetReplacesIt() throws {
        let (state, entry) = try setWithTwoHarmonies()
        let first = state.currentURL!.deletingLastPathComponent().appendingPathComponent("First.bww")
        state.addHarmony(urls: [first], toEntry: entry)
        #expect(state.harmonyNames(ofEntry: entry) == ["First", "Second"])
        #expect(state.engine.segments[0].voices.count == 3)
    }
}


@MainActor
struct MakeSetTests {

    @Test func makeSetKeepsTheTuneItsHarmoniesAndTempo() throws {
        let a = try HarmonyTests.writeTune(named: "A.bww")
        let seconds = a.deletingLastPathComponent().appendingPathComponent("Seconds.bww")
        try FileManager.default.copyItem(at: a, to: seconds)
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.open(url: a)
        state.addHarmony(urls: [seconds])
        state.engine.tempo = 70
        state.makeSet()
        #expect(state.isSet)
        #expect(state.currentURL == nil)
        #expect(state.setList?.entries.count == 1)
        #expect(state.setList?.entries[0].tempo == 70)
        #expect(state.setList?.entries[0].harmonies.count == 1)
        #expect(state.engine.segments[0].voices.count == 2)
    }

    @Test func droppingOnTheBottomStartsASetWithBoth() throws {
        let a = try HarmonyTests.writeTune(named: "A.bww")
        let b = a.deletingLastPathComponent().appendingPathComponent("B.bww")
        try FileManager.default.copyItem(at: a, to: b)
        let state = AppState(recents: AppStateTests.scratchRecents())
        state.open(url: a)
        state.makeSet(adding: [b])
        #expect(state.engine.segments.count == 2)
    }

    @Test func dropZonesInATuneTab() {
        let size = CGSize(width: 400, height: 400)
        #expect(DropZone.at(CGPoint(x: 50, y: 50), in: size, isSet: false) == .open)
        #expect(DropZone.at(CGPoint(x: 350, y: 50), in: size, isSet: false) == .harmony)
        #expect(DropZone.at(CGPoint(x: 350, y: 350), in: size, isSet: false) == .startSet)
        #expect(DropZone.at(CGPoint(x: 50, y: 350), in: size, isSet: false) == .startSet)
    }

    @Test func dropZonesInASetTab() {
        let size = CGSize(width: 400, height: 400)
        #expect(DropZone.at(CGPoint(x: 50, y: 350), in: size, isSet: true) == .addToSet)
        #expect(DropZone.at(CGPoint(x: 350, y: 350), in: size, isSet: true) == .harmony)
    }
}
