import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudioKit
import AppKit

enum PlaybackState: Equatable {
    case stopped, playing, paused
}

/// AVFoundation/AudioToolbox completion handlers hand back plain classes
/// (`AVAudioUnit`, `AVAudioUnitComponent`) and closures that predate Swift
/// concurrency and aren't marked `Sendable`. This is the standard escape
/// hatch for moving a value we know is safe to move (it's only ever touched
/// on one thread at a time, just not provably so to the compiler) across
/// the `DispatchQueue.main.async` isolation boundary.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Owns the audio graph (a bagpipe-timbre `AVAudioUnitSampler`) and the
/// transport state (play/pause/stop/seek/tempo/volume/loop) that the UI binds
/// to. Both local audio and MIDI-out are driven from the same
/// `PlaybackScheduler` so they stay in sync; MIDI-out can be toggled
/// independently of whether local audio is audible.
///
/// `@unchecked Sendable`: `PlaybackScheduler`'s note callbacks fire on its own
/// background queue, while transport actions (play/pause/seek/...) come from
/// SwiftUI on the main thread. The compiler can't verify that's race-free,
/// but it is by construction: the background callbacks only ever touch
/// `sampler`/`midiOutput` (plain imperative calls, not actor-isolated state)
/// and any `@Published` UI-state write originating off the main thread is
/// explicitly marshaled back via `DispatchQueue.main.async` (see
/// `handleFinished`, `tickUIProgress`'s timer, which is itself main-run-loop
/// only). Hopping every single note event onto MainActor instead would add
/// scheduling jitter to fast ornament grace notes, which matters more here
/// than satisfying the checker syntactically.
final class PlaybackEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: PlaybackState = .stopped
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var tempo: Double = 90 {
        didSet { rebuildEvents(preservingPosition: true) }
    }
    /// `tempo` ÷ this factor is what the UI shows/edits — undoes whatever
    /// meter-based scaling the source format's parser already baked into
    /// `tempo` at load time (see `Voice.displayTempoScaleFactor`), so the
    /// tempo field shows the number a player actually wrote/expects (e.g.
    /// 132 for a jig) while `tempo` itself keeps driving playback at the
    /// real speed (e.g. 198).
    private var displayTempoScaleFactor = 1.0
    @Published var volume: Float = 0.8 {
        didSet { sampler.volume = volume }
    }
    @Published var isLooping = false
    @Published var isMIDIOutputEnabled = false
    @Published var instrumentProgram = GeneralMIDI.defaultProgram {
        didSet {
            loadInstrument(program: instrumentProgram)
            UserDefaults.standard.set(instrumentProgram, forKey: Self.instrumentProgramDefaultsKey)
        }
    }
    /// When set, this file is used instead of the system DLS bank — lets the
    /// user pick their own .sf2/.dls soundfont (e.g. a dedicated bagpipe
    /// soundfont) instead of Apple's built-in General MIDI bank.
    @Published private(set) var customSoundFontURL: URL?
    /// When set, this hosted third-party Audio Unit instrument (MainStage,
    /// Kontakt, etc.) receives notes instead of the built-in sampler.
    @Published private(set) var hostedComponent: AVAudioUnitComponent?
    @Published private(set) var isLoadingAudioUnit = false
    /// All simultaneous voices in the currently-loaded tune (just one,
    /// "Melody", for ABC/BWW/BMW; possibly several for a MusicXML harmony
    /// arrangement). Exposed so the UI can offer one mute checkbox per voice.
    @Published private(set) var voices: [Voice] = []
    @Published private(set) var mutedVoiceIDs: Set<String> = []

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var hostedInstrument: AVAudioUnitMIDIInstrument?
    private let midiOutput = MIDIOutputManager()
    private let scheduler = PlaybackScheduler()

    private var events: [ScheduledMIDIEvent] = []
    private var uiTickTimer: Timer?
    private var playbackAnchorWallClock: Date?
    private var playbackAnchorOffset: TimeInterval = 0
    private lazy var dlsSoundBankPath: String? = {
        let candidatePaths = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Sounds/gs_instruments.dls"
        ]
        return candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }()

    var isMIDIOutputAvailable: Bool { midiOutput.isAvailable }

    // Persisted immediately on every change (not just at close/quit) — the
    // same pattern AppState already uses for the recent-files list, and more
    // robust than only saving at specific lifecycle moments (survives a
    // crash or force-quit too).
    private static let instrumentProgramDefaultsKey = "PipePlayer.instrumentProgram"
    private static let customSoundFontDefaultsKey = "PipePlayer.customSoundFontPath"

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        sampler.volume = volume
        restorePersistedInstrumentSelection()
        do {
            try engine.start()
        } catch {
            print("PipePlayer: audio engine failed to start (\(error)). Local audio will be silent; MIDI-out still works.")
        }
    }

    /// Restores the last-used instrument/SoundFont across launches. AU
    /// hosting isn't restored here — a hosted plugin is identified by
    /// re-enumerating installed components, which is a different, more
    /// fragile problem than remembering a GM program number or a file path.
    private func restorePersistedInstrumentSelection() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: Self.customSoundFontDefaultsKey),
           FileManager.default.fileExists(atPath: path) {
            customSoundFontURL = URL(fileURLWithPath: path)
        }
        if let savedProgram = defaults.object(forKey: Self.instrumentProgramDefaultsKey) as? Int {
            instrumentProgram = savedProgram // didSet -> loadInstrument(program:), using customSoundFontURL above if set
        } else {
            loadInstrument(program: instrumentProgram) // no saved program — still need one initial load
        }
    }

    /// Switches to a user-supplied SoundFont (.sf2) or DLS file, replacing
    /// Apple's built-in General MIDI bank as the source for `instrumentProgram`.
    /// Resets to program 0 since a custom file's own program layout (often a
    /// single dedicated instrument) rarely lines up with GM program 109
    /// ("Bagpipe") — the instrument picker stays enabled afterward so the
    /// user can still try other program numbers within that file.
    func useCustomSoundFont(at url: URL) {
        detachHostedInstrument()
        customSoundFontURL = url
        UserDefaults.standard.set(url.path, forKey: Self.customSoundFontDefaultsKey)
        instrumentProgram = 0 // triggers loadInstrument + persists instrumentProgram via didSet
    }

    /// Reverts to Apple's built-in General MIDI DLS bank.
    func useBuiltInSoundBank() {
        detachHostedInstrument()
        customSoundFontURL = nil
        UserDefaults.standard.removeObject(forKey: Self.customSoundFontDefaultsKey)
        loadInstrument(program: instrumentProgram)
    }

    /// Instantiates `component` (asynchronously — third-party AUs can take a
    /// noticeable moment to load) and, once ready, swaps it into the audio
    /// graph as the note-receiving instrument in place of the built-in
    /// sampler. Any previously hosted AU is detached first.
    func useAudioUnit(_ component: AVAudioUnitComponent) {
        isLoadingAudioUnit = true
        let boxedComponent = UncheckedSendableBox(component)
        AVAudioUnit.instantiate(with: component.audioComponentDescription, options: []) { [weak self] avAudioUnit, error in
            let boxedResult = UncheckedSendableBox((avAudioUnit, error))
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingAudioUnit = false
                let (avAudioUnit, error) = boxedResult.value
                let component = boxedComponent.value
                guard let avAudioUnit, error == nil else {
                    print("PipePlayer: couldn't load \(component.name) (\(error?.localizedDescription ?? "unknown error")).")
                    return
                }
                self.attachHostedInstrument(avAudioUnit, component: component)
            }
        }
    }

    /// Requests the hosted AU's own view controller (e.g. Kontakt's or
    /// MainStage's patch browser) so the user can pick sounds within it —
    /// there's no universal cross-plugin "program change" API, so browsing
    /// patches inside a hosted third-party instrument means showing its own UI.
    func requestHostedInstrumentViewController(completion: @escaping (NSViewController?) -> Void) {
        guard let hosted = hostedInstrument else { completion(nil); return }
        let boxedCompletion = UncheckedSendableBox(completion)
        hosted.auAudioUnit.requestViewController { viewController in
            let boxedViewController = UncheckedSendableBox(viewController)
            DispatchQueue.main.async { boxedCompletion.value(boxedViewController.value) }
        }
    }

    private func attachHostedInstrument(_ avAudioUnit: AVAudioUnit, component: AVAudioUnitComponent) {
        silenceAllNotes()
        engine.pause()
        if let old = hostedInstrument {
            engine.disconnectNodeOutput(old)
            engine.detach(old)
        }
        engine.attach(avAudioUnit)
        engine.connect(avAudioUnit, to: engine.mainMixerNode, format: nil)
        hostedInstrument = avAudioUnit as? AVAudioUnitMIDIInstrument
        hostedComponent = component
        do {
            try engine.start()
        } catch {
            print("PipePlayer: audio engine failed to restart after loading \(component.name) (\(error)).")
        }
    }

    private func detachHostedInstrument() {
        guard let old = hostedInstrument else { return }
        silenceAllNotes()
        engine.pause()
        engine.disconnectNodeOutput(old)
        engine.detach(old)
        hostedInstrument = nil
        hostedComponent = nil
        do {
            try engine.start()
        } catch {
            print("PipePlayer: audio engine failed to restart after unloading the plugin (\(error)).")
        }
    }

    /// Loads a General MIDI instrument patch from either the user's chosen
    /// SoundFont/DLS file or, by default, Apple's built-in DLS sound bank
    /// (ships with macOS, so no bundled soundfont asset is needed). Falls
    /// back silently (with a log) if no bank can be found, since exact
    /// system paths can shift across releases.
    private func loadInstrument(program: Int) {
        silenceAllNotes()
        guard let path = customSoundFontURL?.path ?? dlsSoundBankPath else {
            print("PipePlayer: couldn't find the system DLS sound bank; local audio playback will be silent.")
            return
        }
        do {
            try sampler.loadSoundBankInstrument(
                at: URL(fileURLWithPath: path),
                program: UInt8(program),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            print("PipePlayer: couldn't load \(GeneralMIDI.name(forProgram: program)) from \(path) (\(error)); local audio playback will be silent.")
        }
    }

    func load(voices newVoices: [Voice]) {
        stop()
        voices = newVoices
        mutedVoiceIDs = []
        displayTempoScaleFactor = newVoices.first?.displayTempoScaleFactor ?? 1.0
        tempo = newVoices.first?.tune.tempo ?? 90
        rebuildEvents(preservingPosition: false)
    }

    /// The tempo number the UI shows and edits — e.g. 132 for a jig whose
    /// actual playback `tempo` is the quarter-note-equivalent 198. For a
    /// format/meter with no scaling (MusicXML, or BWW/BMW simple time) the
    /// two are identical.
    var displayTempo: Double {
        get { tempo / displayTempoScaleFactor }
        set { tempo = newValue * displayTempoScaleFactor }
    }

    /// Mutes/unmutes one voice (e.g. a harmony part) and rebuilds the merged
    /// playback timeline. Muting is audio-only — it never changes `duration`,
    /// which always reflects the longest voice regardless of mute state, so
    /// the scrubber doesn't jump around as the user toggles checkboxes.
    func setVoiceMuted(id: String, muted: Bool) {
        if muted { mutedVoiceIDs.insert(id) } else { mutedVoiceIDs.remove(id) }
        rebuildEvents(preservingPosition: true)
    }

    private func rebuildEvents(preservingPosition: Bool) {
        let perVoiceEvents = voices.map { voice in
            (id: voice.id, events: MIDIEventBuilder.buildEvents(for: voice.tune, tempoOverride: tempo))
        }
        duration = perVoiceEvents.map { MIDIEventBuilder.totalDuration(of: $0.events) }.max() ?? 0
        events = perVoiceEvents
            .filter { !mutedVoiceIDs.contains($0.id) }
            .flatMap(\.events)
            .sorted { $0.time < $1.time }
        if !preservingPosition {
            currentTime = 0
        } else if state == .playing {
            // Tempo/mute changed mid-playback — restart the scheduler at the
            // same musical position under the new event timing.
            startScheduler(from: currentTime)
        }
    }

    // MARK: - Transport

    func play() {
        guard !events.isEmpty else { return }
        state = .playing
        startScheduler(from: currentTime)
        startUITicking()
    }

    func pause() {
        scheduler.stop()
        stopUITicking()
        state = .paused
        silenceAllNotes()
    }

    func stop() {
        scheduler.stop()
        stopUITicking()
        state = .stopped
        currentTime = 0
        silenceAllNotes()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = state == .playing
        scheduler.stop()
        silenceAllNotes()
        currentTime = max(0, min(time, duration))
        if wasPlaying {
            startScheduler(from: currentTime)
        }
    }

    private func startScheduler(from time: TimeInterval) {
        playbackAnchorWallClock = Date()
        playbackAnchorOffset = time
        scheduler.start(
            events: events,
            from: time,
            onNoteOn: { [weak self] note, velocity in self?.handleNoteOn(note, velocity) },
            onNoteOff: { [weak self] note in self?.handleNoteOff(note) },
            onFinished: { [weak self] in self?.handleFinished() }
        )
    }

    // MARK: - Note dispatch (runs on the scheduler's background queue)

    private var activeInstrument: AVAudioUnitMIDIInstrument {
        hostedInstrument ?? sampler
    }

    // Reference-counts how many currently-sounding voices hold each pitch.
    // With multiple simultaneous voices (a MusicXML harmony arrangement)
    // sharing the same 9-note chanter scale, two voices landing on the same
    // pitch at once is common (e.g. parallel thirds/unisons) — without this,
    // one voice's note-off would silence a pitch the other voice is still
    // holding. Guarded by a lock since note-on/off normally run serially on
    // `PlaybackScheduler`'s dedicated thread, but `silenceAllNotes()` can also
    // be called from the main thread (stop/pause/seek).
    private let noteCountLock = NSLock()
    private var activeNoteCounts: [UInt8: Int] = [:]

    private func handleNoteOn(_ note: UInt8, _ velocity: UInt8) {
        noteCountLock.lock()
        let previousCount = activeNoteCounts[note, default: 0]
        activeNoteCounts[note] = previousCount + 1
        noteCountLock.unlock()
        guard previousCount == 0 else { return }
        activeInstrument.startNote(note, withVelocity: velocity, onChannel: 0)
        if isMIDIOutputEnabled { midiOutput.sendNoteOn(note: note, velocity: velocity) }
    }

    private func handleNoteOff(_ note: UInt8) {
        noteCountLock.lock()
        let previousCount = activeNoteCounts[note, default: 0]
        let newCount = max(0, previousCount - 1)
        activeNoteCounts[note] = newCount
        noteCountLock.unlock()
        guard previousCount > 0, newCount == 0 else { return }
        activeInstrument.stopNote(note, onChannel: 0)
        if isMIDIOutputEnabled { midiOutput.sendNoteOff(note: note) }
    }

    private func silenceAllNotes() {
        noteCountLock.lock()
        activeNoteCounts.removeAll()
        noteCountLock.unlock()
        let instrument = activeInstrument
        for n: UInt8 in 0...127 { instrument.stopNote(n, onChannel: 0) }
        midiOutput.sendAllNotesOff()
    }

    private func handleFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isLooping {
                self.currentTime = 0
                self.play()
            } else {
                self.stopUITicking()
                self.state = .stopped
                self.currentTime = 0
            }
        }
    }

    // MARK: - UI progress ticking (smooth scrubber independent of sparse note events)

    private func startUITicking() {
        stopUITicking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickUIProgress()
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTickTimer = timer
    }

    private func stopUITicking() {
        uiTickTimer?.invalidate()
        uiTickTimer = nil
    }

    private func tickUIProgress() {
        guard state == .playing, let anchor = playbackAnchorWallClock else { return }
        let elapsed = playbackAnchorOffset + Date().timeIntervalSince(anchor)
        currentTime = min(elapsed, duration)
    }
}
