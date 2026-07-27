import SwiftUI

/// One mute checkbox per simultaneous voice. Only meaningful — and only
/// shown by `ContentView` — when a tune has more than one voice, i.e. a
/// MusicXML harmony arrangement with bridged staves (melody + harmony parts)
/// meant to play together. ABC/BWW/BMW and single-part MusicXML always
/// produce exactly one voice, so this view never appears for those.
struct VoiceMuteControlsView: View {
    @ObservedObject var engine: PlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voices")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(engine.voices) { voice in
                    Toggle(voice.name, isOn: Binding(
                        get: { !engine.mutedVoiceIDs.contains(voice.id) },
                        set: { engine.setVoiceMuted(id: voice.id, muted: !$0) }
                    ))
                    .toggleStyle(.checkbox)
                }
                Spacer()
            }
        }
    }
}
