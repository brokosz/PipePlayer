import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct TransportControlsView: View {
    @ObservedObject var engine: PlaybackEngine
    @State private var availableAudioUnits: [AVAudioUnitComponent] = []
    @State private var pluginWindowController: PluginWindowController?

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
                    TextField("Tempo", value: tempoBinding, format: .number)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: tempoBinding, in: 40...248)
                        .labelsHidden()
                    Text("BPM")
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Volume") {
                Slider(value: $engine.volume, in: 0...1)
            }

            LabeledContent("Instrument") {
                HStack(spacing: 6) {
                    Picker("", selection: $engine.instrumentProgram) {
                        ForEach(GeneralMIDI.names.indices, id: \.self) { program in
                            Text(GeneralMIDI.names[program]).tag(program)
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

    private var tempoBinding: Binding<Int> {
        Binding(
            get: { Int(engine.displayTempo.rounded()) },
            set: { engine.displayTempo = Double(min(248, max(40, $0))) }
        )
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { engine.currentTime },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...max(engine.duration, 0.01)
            )
            HStack {
                Text(formatted(engine.currentTime))
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
