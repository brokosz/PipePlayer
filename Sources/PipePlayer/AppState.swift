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

    /// The primary voice's tune with embellishments already expanded —
    /// what `PartProgressView` measures its part spans against. Grace notes
    /// add a small sliver of real playback time rather than borrowing it from
    /// the note they decorate (see `EmbellishmentExpander`), so a progress
    /// bar computed from *un*-expanded note durations would fall increasingly
    /// behind the real audio, finishing each part before it's actually done.
    /// `MIDIEventBuilder` expands internally too — this is computed once
    /// here (not per SwiftUI body re-render) so both sides agree on the same
    /// timeline without re-running the expansion dozens of times a second.
    /// Same goes for `PerformanceStyle`: a pointed strathspey's cuts land
    /// at different spots inside the beat than written.
    @Published private(set) var progressTune: Tune?

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
    }

    /// Static so File → Open works with no window open at all — there's no
    /// AppState to call it on until a window exists. Several files at once
    /// open one per tab (see `TuneOpener`).
    static func chooseTuneFiles() -> [URL] {
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
        do {
            let loadedVoices = try TuneFileLoader.loadVoices(from: url)
            let alignedVoices = VoiceAligner.align(loadedVoices)
            melodyVoices = alignedVoices
            harmonies = []
            nextHarmonyNumber = 0
            voices = alignedVoices
            progressTune = alignedVoices.first.map { EmbellishmentExpander.expand(tune: PerformanceStyle.apply(to: $0.tune)) }
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
        guard let index = harmonies.firstIndex(where: { $0.voices.contains { $0.id == voiceID } }) else { return }
        harmonies.remove(at: index)
        reloadVoices()
    }

    func isHarmony(_ voiceID: String) -> Bool {
        harmonies.contains { $0.voices.contains { $0.id == voiceID } }
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
        for id in mutes where combined.contains(where: { $0.id == id }) {
            engine.setVoiceMuted(id: id, muted: true)
        }
        engine.seek(to: time)
        if wasPlaying { engine.play() }
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
        progressTune = nil
        currentURL = nil
    }
}
