import Foundation
import AppKit
import UniformTypeIdentifiers

/// One tab's tune and `PlaybackEngine` — shared between `ContentView` and
/// the File menu commands (which live at the Scene level, outside the view
/// hierarchy, so they need a reference to the same state rather than
/// view-local `@State`). The recent-files list is app-wide: `RecentTunes`.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var voices: [Voice] = []
    @Published var errorMessage: String?
    /// The file this window's tune came from — what `ContentView` persists
    /// so the tab can reopen it after a relaunch.
    @Published private(set) var currentURL: URL?

    /// The primary voice's tune — drives the window title. For a multi-voice
    /// MusicXML harmony arrangement this is the first `<part>` (conventionally
    /// the melody); every voice still contributes audio via `engine`,
    /// independent of what's shown here.
    var tune: Tune? { voices.first?.tune }

    /// The window (or tab) showing this state, set by `ContentView` — what
    /// `TuneOpener` brings forward when a file that's already open here is
    /// opened again.
    weak var window: NSWindow?


    let engine = PlaybackEngine()
    // Retained here so its Combine subscriptions (which keep the media-key
    // now-playing info in sync with playback) stay alive for the app's
    // lifetime — see NowPlayingController.
    private var nowPlayingController: NowPlayingController?

    let recents: RecentTunes

    init(recents: RecentTunes = .shared) {
        self.recents = recents
        OpenTabs.shared.register(self)
        nowPlayingController = NowPlayingController(engine: engine)
        engine.onSegmentTempoChange = { [weak self] index, tempo in
            MainActor.assumeIsolated { self?.segmentTempoChanged(index, tempo) }
        }
    }

    /// True for a tab with nothing in it — no tune and no set — which a
    /// newly opened file may take over.
    var isEmptyTab: Bool { tune == nil && !isSet }

    /// Static so File → Open works with no window open at all — there's no
    /// AppState to call it on until a window exists. Several files at once
    /// open one per tab (see `TuneOpener`).
    static func chooseTuneFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = (TuneFileLoader.supportedExtensions + [SetList.fileExtension]).compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// Tunes only — what a set's + button offers.
    static func chooseSetTuneFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = TuneFileLoader.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    func bringToFront() {
        // Deferred a turn: when the request came from Finder, SwiftUI
        // re-fronts whichever tab received the event right after this
        // returns, undoing an immediate switch.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp?.activate(ignoringOtherApps: true)
            // A background tab ignores makeKeyAndOrderFront on its own — it
            // has to be selected in its tab group first.
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// `addToRecents: false` is for restoring a tab's tune on relaunch —
    /// reopening every restored tab shouldn't reshuffle Open Recent into
    /// whatever order the windows happened to come back in.
    func open(url: URL, addToRecents: Bool = true) {
        if url.pathExtension.lowercased() == SetList.fileExtension {
            openSet(url: url, addToRecents: addToRecents)
            return
        }
        do {
            let loadedVoices = try TuneFileLoader.loadVoices(from: url)
            let alignedVoices = VoiceAligner.align(loadedVoices)
            setList = nil
            setHarmonyOwners = [:]
            melodyVoices = alignedVoices
            harmonies = []
            nextHarmonyNumber = 0
            voices = alignedVoices
            engine.load(voices: alignedVoices)
            currentURL = url
            if addToRecents { recents.add(url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Harmony

    /// The tune's own voices, before any added harmony.
    private var melodyVoices: [Voice] = []
    /// Harmony files added to this tab, each with the voices it produced.
    private var harmonies: [(url: URL, voices: [Voice])] = [] {
        didSet { harmonyURLs = harmonies.map(\.url) }
    }
    private var nextHarmonyNumber = 0

    /// The files added as harmony, in order — what `ContentView` persists.
    @Published private(set) var harmonyURLs: [URL] = []

    /// Adds each file's voices to the tune, fitted to the melody part by
    /// part (`VoiceAligner.fit`). Playback carries on from the same place,
    /// at the same tempo, with existing mutes kept. A file that won't load
    /// is reported and skipped.
    func addHarmony(urls: [URL]) {
        if isSet {
            let index = engine.currentSegmentIndex
            if segmentEntryIDs.indices.contains(index) {
                addHarmony(urls: urls, toEntry: segmentEntryIDs[index])
            }
            return
        }
        guard let melody = melodyVoices.first?.tune else { return }
        var added = false
        for url in urls {
            do {
                let loaded = try TuneFileLoader.loadVoices(from: url)
                let fileName = url.deletingPathExtension().lastPathComponent
                let number = nextHarmonyNumber
                nextHarmonyNumber += 1
                let voices = loaded.map { voice in
                    Voice(
                        id: "harmony-\(number)-\(voice.id)",
                        name: loaded.count > 1 ? "\(fileName) – \(voice.name)" : fileName,
                        tune: VoiceAligner.fit(voice.tune, to: melody)
                    )
                }
                harmonies.append((url, voices))
                added = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if added { reloadVoices() }
    }

    /// Removes the harmony file `voiceID` came from — all of its voices.
    func removeHarmony(voiceID: String) {
        if let owner = setHarmonyOwners[voiceID] {
            setList?.removeHarmony(at: owner.index, fromEntry: owner.entry)
            setChanged()
            return
        }
        guard let index = harmonies.firstIndex(where: { $0.voices.contains { $0.id == voiceID } }) else { return }
        harmonies.remove(at: index)
        reloadVoices()
    }

    func isHarmony(_ voiceID: String) -> Bool {
        setHarmonyOwners[voiceID] != nil || harmonies.contains { $0.voices.contains { $0.id == voiceID } }
    }

    private func reloadVoices() {
        let tempo = engine.tempo
        let mutes = engine.mutedVoiceIDs
        let time = engine.currentTime
        let wasPlaying = engine.state == .playing
        let combined = melodyVoices + harmonies.flatMap(\.voices)
        voices = combined
        engine.load(voices: combined)
        if engine.tempo != tempo { engine.tempo = tempo }
        // With the harmony gone there's no mute row to undo a muted melody
        // with — it would leave a silent tab — so mutes go with the last one.
        for id in mutes where !harmonies.isEmpty && combined.contains(where: { $0.id == id }) {
            engine.setVoiceMuted(id: id, muted: true)
        }
        engine.seek(to: time)
        if wasPlaying { engine.play() }
    }

    // MARK: - Sets

    /// The set this tab holds, if it holds one rather than a single tune.
    @Published private(set) var setList: SetList?
    var isSet: Bool { setList != nil }
    /// Why an entry isn't playing (file missing, won't parse), by entry id.
    @Published private(set) var entryProblems: [UUID: String] = [:]
    /// Titles of the tunes that loaded, in play order — one per segment.
    @Published private(set) var segmentTitles: [String] = []
    /// The entry behind each loaded segment (problem entries are skipped).
    private var segmentEntryIDs: [UUID] = []
    /// Which entry, and which of its harmonies, each set harmony voice is.
    private var setHarmonyOwners: [String: (entry: UUID, index: Int)] = [:]
    /// Harmony names per entry, for the list ("(missing)" when not found).
    private var entryHarmonyNames: [UUID: [String]] = [:]

    func harmonyNames(ofEntry id: UUID) -> [String] {
        entryHarmonyNames[id] ?? []
    }

    /// Adds harmony files to one tune of the set and saves. A file that
    /// won't load is reported and not added.
    func addHarmony(urls: [URL], toEntry id: UUID) {
        guard isSet else { return }
        var added = false
        for url in urls {
            do {
                _ = try TuneFileLoader.loadVoices(from: url)
                setList?.addHarmony(url, toEntry: id, relativeTo: currentURL)
                added = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if added { setChanged() }
    }

    /// Saves this tune and its harmonies as a one-tune set — a pairing that
    /// reopens together — and turns the tab into that set.
    func saveTuneAsSet(to url: URL) throws {
        guard !isSet, let tuneURL = currentURL else { return }
        var set = SetList(name: url.deletingPathExtension().lastPathComponent, entries: [])
        set.append(tuneURL, relativeTo: url)
        set.entries[0].tempo = tempoOverride
        for harmony in harmonyURLs {
            set.addHarmony(harmony, toEntry: set.entries[0].id, relativeTo: url)
        }
        try set.write(to: url)
        openSet(url: url, addToRecents: true)
    }

    /// Asks where to save this tune and its harmonies as a set.
    func chooseLocationAndSaveTuneAsSet() {
        guard let name = currentURL?.deletingPathExtension().lastPathComponent else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: SetList.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = "\(name).\(SetList.fileExtension)"
        panel.directoryURL = currentURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try saveTuneAsSet(to: url) } catch { errorMessage = error.localizedDescription }
    }

    /// A new, empty, untitled set in this tab.
    func newSet() {
        resetForSet(SetList(name: "Untitled Set", entries: []), url: nil)
    }

    /// Restores an untitled set (from the tab's saved state).
    func restoreUntitledSet(_ set: SetList) {
        resetForSet(set, url: nil)
    }

    private func openSet(url: URL, addToRecents: Bool) {
        do {
            resetForSet(try SetList.load(from: url), url: url)
            if addToRecents { recents.add(url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetForSet(_ set: SetList, url: URL?) {
        engine.stop()
        voices = []
        melodyVoices = []
        harmonies = []
        setList = set
        currentURL = url
        reloadSet()
    }

    func addToSet(urls: [URL]) {
        guard setList != nil else { return }
        for url in urls { setList?.append(url, relativeTo: currentURL) }
        setChanged()
    }

    func removeFromSet(id: UUID) {
        setList?.entries.removeAll { $0.id == id }
        setChanged()
    }

    func moveSetEntries(from source: IndexSet, to destination: Int) {
        setList?.entries.move(fromOffsets: source, toOffset: destination)
        setChanged()
    }

    /// Saves the set to `url` — the first save of an untitled set, or a
    /// save elsewhere. Later edits save there automatically.
    func saveSet(to url: URL) throws {
        guard var set = setList else { return }
        set.rebase(to: url, from: currentURL)
        set.name = url.deletingPathExtension().lastPathComponent
        try set.write(to: url)
        setList = set
        currentURL = url
        recents.add(url)
    }

    /// Asks where to save an untitled set, then saves it there.
    func chooseLocationAndSaveSet() {
        guard let set = setList else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: SetList.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = "\(set.name).\(SetList.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try saveSet(to: url) } catch { errorMessage = error.localizedDescription }
    }

    /// The segment an entry plays as, or nil when it has a problem.
    func segmentIndex(ofEntry id: UUID) -> Int? {
        segmentEntryIDs.firstIndex(of: id)
    }

    private func setChanged() {
        reloadSet()
        writeSet()
    }

    private func writeSet() {
        guard let set = setList, let url = currentURL else { return }
        do { try set.write(to: url) } catch { errorMessage = error.localizedDescription }
    }

    /// Rebuilds the engine's segments from the set. Playback stays at the
    /// same spot in the tune that was playing if that tune is still there;
    /// otherwise it goes back to the start.
    private func reloadSet() {
        guard let set = setList else { return }
        let wasPlaying = engine.state == .playing
        let index = engine.currentSegmentIndex
        let playingID = segmentEntryIDs.indices.contains(index) ? segmentEntryIDs[index] : nil
        let offset = engine.segmentStarts.indices.contains(index) ? engine.currentTime - engine.segmentStarts[index] : 0

        var segments: [PlaybackSegment] = []
        var ids: [UUID] = []
        var titles: [String] = []
        var problems: [UUID: String] = [:]
        var owners: [String: (entry: UUID, index: Int)] = [:]
        var harmonyNames: [UUID: [String]] = [:]
        for entry in set.entries {
            guard let url = set.url(for: entry, relativeTo: currentURL) else {
                problems[entry.id] = "File not found"
                continue
            }
            do {
                // Ids carry the entry so mutes stay with one tune of the set.
                let melody = VoiceAligner.align(try TuneFileLoader.loadVoices(from: url)).map {
                    Voice(id: "\(entry.id)-\($0.id)", name: $0.name, tune: $0.tune, displayTempoScaleFactor: $0.displayTempoScaleFactor)
                }
                guard let first = melody.first else { throw TuneFileLoaderError.unsupportedExtension(url.pathExtension) }
                var voices = melody
                var names: [String] = []
                for (h, ref) in entry.harmonies.enumerated() {
                    let fallbackName = ref.relativePath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "Harmony"
                    // A harmony that's gone doesn't stop the tune.
                    guard let harmonyURL = set.url(for: ref, relativeTo: currentURL),
                          let loaded = try? TuneFileLoader.loadVoices(from: harmonyURL) else {
                        names.append("\(fallbackName) (missing)")
                        continue
                    }
                    let fileName = harmonyURL.deletingPathExtension().lastPathComponent
                    names.append(fileName)
                    for voice in loaded {
                        let id = "\(entry.id)-h\(h)-\(voice.id)"
                        owners[id] = (entry.id, h)
                        voices.append(Voice(
                            id: id,
                            name: loaded.count > 1 ? "\(fileName) – \(voice.name)" : fileName,
                            tune: VoiceAligner.fit(voice.tune, to: first.tune)
                        ))
                    }
                }
                harmonyNames[entry.id] = names
                segments.append(PlaybackSegment(
                    voices: voices,
                    tempo: entry.tempo ?? first.tune.tempo,
                    displayTempoScaleFactor: first.displayTempoScaleFactor
                ))
                ids.append(entry.id)
                titles.append(first.tune.title.isEmpty ? url.deletingPathExtension().lastPathComponent : first.tune.title)
            } catch {
                problems[entry.id] = error.localizedDescription
            }
        }
        let previousIDs = segmentEntryIDs
        segmentEntryIDs = ids
        segmentTitles = titles
        entryProblems = problems
        setHarmonyOwners = owners
        entryHarmonyNames = harmonyNames
        engine.load(segments: segments, keepingMutes: true)
        if let playingID, let newIndex = ids.firstIndex(of: playingID) {
            engine.seek(to: engine.segmentStarts[newIndex] + offset)
            if wasPlaying { engine.play() }
        } else if playingID != nil, let playingEntry = previousIDs.firstIndex(of: playingID!),
                  let next = previousIDs[(playingEntry + 1)...].first(where: { ids.contains($0) }),
                  let nextIndex = ids.firstIndex(of: next) {
            // The playing tune was removed: carry on from the next one.
            engine.seek(to: engine.segmentStarts[nextIndex])
            if wasPlaying { engine.play() }
        }
    }

    private func segmentTempoChanged(_ index: Int, _ tempo: Double) {
        guard segmentEntryIDs.indices.contains(index),
              let entryIndex = setList?.entries.firstIndex(where: { $0.id == segmentEntryIDs[index] }) else { return }
        setList?.entries[entryIndex].tempo = tempo
        writeSet()
    }

    // MARK: - Per-tab playback settings

    /// The tempo this tab plays at, when it isn't the file's own — what
    /// `ContentView` persists per tab. Raw playback tempo, not the
    /// meter-scaled number the tempo field shows.
    var tempoOverride: Double? {
        guard let fileTempo = tune?.tempo, engine.tempo != fileTempo else { return nil }
        return engine.tempo
    }

    /// Puts back a restored tab's tempo and voice mutes once its tune is
    /// loaded (loading resets both). Voice IDs the file no longer has are
    /// ignored — it may have been edited since.
    func applyPlaybackSettings(tempoOverride: Double?, mutedVoiceIDs: Set<String>) {
        guard let tune else { return }
        let target = tempoOverride ?? tune.tempo
        if engine.tempo != target { engine.tempo = target }
        for voice in voices {
            let shouldMute = mutedVoiceIDs.contains(voice.id)
            if engine.mutedVoiceIDs.contains(voice.id) != shouldMute {
                engine.setVoiceMuted(id: voice.id, muted: shouldMute)
            }
        }
    }

    func closeTune() {
        engine.stop()
        voices = []
        melodyVoices = []
        harmonies = []
        setList = nil
        setHarmonyOwners = [:]
        entryHarmonyNames = [:]
        segmentEntryIDs = []
        segmentTitles = []
        entryProblems = [:]
        currentURL = nil
    }
}
