import SwiftUI

/// One mute checkbox per voice of the tune at the playhead — a MusicXML
/// arrangement's parts, or harmony files added to the tune. Shown by
/// `ContentView` only when there's more than one. Added harmonies also get
/// a remove button.
struct VoiceMuteControlsView: View {
    @ObservedObject var engine: PlaybackEngine
    /// Added harmony voices get a Remove Harmony item on right-click.
    var isHarmony: (String) -> Bool = { _ in false }
    var onRemoveHarmony: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voices")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(engine.currentVoices) { voice in
                    HStack(spacing: 4) {
                        Toggle(voice.name, isOn: Binding(
                            get: { !engine.mutedVoiceIDs.contains(voice.id) },
                            set: { engine.setVoiceMuted(id: voice.id, muted: !$0) }
                        ))
                        .toggleStyle(.checkbox)
                        if isHarmony(voice.id) {
                            Button {
                                onRemoveHarmony(voice.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove Harmony")
                        }
                    }
                    .contextMenu {
                        if isHarmony(voice.id) {
                            Button("Remove Harmony") { onRemoveHarmony(voice.id) }
                        }
                    }
                }
                Spacer()
            }
        }
    }
}
