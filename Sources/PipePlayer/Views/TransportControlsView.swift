import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(upperBound, Swift.max(lowerBound, value)) }
}

struct TransportControlsView: View {
    @ObservedObject var engine: PlaybackEngine
    @State private var availableAudioUnits: [AVAudioUnitComponent] = []
    @State private var pluginWindowController: PluginWindowController?
    @State private var isScrubbing = false
    @State private var scrubberValue: TimeInterval = 0
    @FocusState private var isTempoFieldFocused: Bool
    @State private var tempoDraftText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            scrubber

            HStack(spacing: 20) {
                Button(action: engine.stop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)

                Button(action: togglePlayPause) {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)

                Toggle(isOn: $engine.isLooping) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)
                .help("Loop")

                Toggle(isOn: $engine.isDroneEnabled) {
                    Image(systemName: "waveform")
                }
                .toggleStyle(.button)
                .help("Drone — a continuous bagpipe drone underneath the melody (needs a soundfont with a drone sample, like the bundled PipeDrones.sf2)")

                Spacer()

                Toggle(isOn: $engine.isMIDIOutputEnabled) {
                    Label("MIDI Out", systemImage: "pianokeys")
                }
                .toggleStyle(.button)
                .disabled(!engine.isMIDIOutputAvailable)
                .help(engine.isMIDIOutputAvailable
                      ? "Send this tune out the \"PipePlayer\" virtual MIDI port"
                      : "Virtual MIDI port unavailable")
            }

            LabeledContent("Tempo") {
                HStack(spacing: 6) {
                    TextField("Tempo", text: $tempoDraftText)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTempoFieldFocused)
                        .onSubmit { commitTempoDraft() }
                    Stepper("", value: tempoBinding, in: Self.tempoRange)
                        .labelsHidden()
                    Text("BPM")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { tempoDraftText = String(Int(engine.displayTempo.rounded())) }
            .onChange(of: engine.displayTempo) { newValue in
                guard !isTempoFieldFocused else { return }
                tempoDraftText = String(Int(newValue.rounded()))
            }
            .onChange(of: isTempoFieldFocused) { focused in
                if !focused { commitTempoDraft() }
            }

            LabeledContent("Volume") {
                Slider(value: $engine.volume, in: 0...1)
            }

            LabeledContent("Instrument") {
                HStack(spacing: 6) {
                    Picker("", selection: $engine.instrumentProgram) {
                        if !engine.customSoundFontPresets.isEmpty {
                            ForEach(engine.customSoundFontPresets, id: \.program) { preset in
                                Text(preset.name).tag(preset.program)
                            }
                        } else {
                            ForEach(GeneralMIDI.names.indices, id: \.self) { program in
                                Text(GeneralMIDI.names[program]).tag(program)
                            }
                        }
                    }
                    .labelsHidden()
                    .disabled(engine.hostedComponent != nil)

                    Button {
                        presentSoundFontPanel()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .disabled(engine.hostedComponent != nil)
                    .help("Load a custom SoundFont (.sf2) or DLS file")
                }
            }

            if let soundFontURL = engine.customSoundFontURL, engine.hostedComponent == nil {
                HStack {
                    Text("Using SoundFont: \(soundFontURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Built-in General MIDI") {
                        engine.useBuiltInSoundBank()
                    }
                    .font(.caption)
                }
            }

            LabeledContent("Plugin") {
                HStack(spacing: 6) {
                    Menu(engine.hostedComponent?.name ?? "None (use SoundFont above)") {
                        Button("None (use SoundFont above)") {
                            engine.useBuiltInSoundBank()
                        }
                        if !availableAudioUnits.isEmpty {
                            Divider()
                            ForEach(Array(availableAudioUnits.enumerated()), id: \.offset) { _, component in
                                Button("\(component.name) — \(component.manufacturerName)") {
                                    engine.useAudioUnit(component)
                                }
                            }
                        }
                    }
                    if engine.isLoadingAudioUnit {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if engine.hostedComponent != nil {
                        Button("Show Plugin Window") {
                            showPluginWindow()
                        }
                    }
                }
            }
        }
        .onAppear {
            availableAudioUnits = AudioUnitCatalog.availableInstruments()
        }
    }

    private func showPluginWindow() {
        engine.requestHostedInstrumentViewController { viewController in
            guard let viewController else { return }
            let controller = PluginWindowController(
                viewController: viewController,
                title: engine.hostedComponent?.name ?? "Plugin"
            )
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            pluginWindowController = controller
        }
    }

    private func presentSoundFontPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["sf2", "dls"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.useCustomSoundFont(at: url)
    }

    // A densely-ornamented slow air can genuinely need a much slower feel
    // than the same BPM number gives a plainer tune of the same nominal
    // type — 40 was too high a floor to dial some of those down to.
    private static let tempoRange = 20...248

    private var tempoBinding: Binding<Int> {
        Binding(
            get: { Int(engine.displayTempo.rounded()) },
            set: { engine.displayTempo = Double(Self.tempoRange.clamp($0)) }
        )
    }

    /// The tempo field commits only when the user finishes editing (Return
    /// key or focus loss), not on every keystroke — typing directly into a
    /// `TextField(value:format:)` bound live to `engine.displayTempo` meant
    /// each intermediate digit (e.g. the "8" in "82") briefly set a real,
    /// wildly different tempo, which rebuilds the playback schedule and
    /// silences/restarts mid-note if a tune is playing. A plain `String`
    /// draft that's only parsed and applied here avoids that entirely.
    private func commitTempoDraft() {
        guard let parsed = Int(tempoDraftText) else {
            tempoDraftText = String(Int(engine.displayTempo.rounded()))
            return
        }
        engine.displayTempo = Double(Self.tempoRange.clamp(parsed))
        tempoDraftText = String(Int(engine.displayTempo.rounded()))
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubberValue : engine.currentTime },
                    set: { scrubberValue = $0 }
                ),
                in: 0...max(engine.duration, 0.01),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    // Committing on every intermediate drag value (rather
                    // than just on release) meant dozens of full stop/
                    // silence-all-notes/restart cycles per second while
                    // dragging — real audio-engine churn, not just a UI
                    // nicety. Only seek once, when the drag actually ends.
                    if !editing { engine.seek(to: scrubberValue) }
                }
            )
            HStack {
                Text(formatted(isScrubbing ? scrubberValue : engine.currentTime))
                Spacer()
                Text(formatted(engine.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func togglePlayPause() {
        if engine.state == .playing {
            engine.pause()
        } else {
            engine.play()
        }
    }

    private func formatted(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
