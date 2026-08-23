import Foundation
import UniformTypeIdentifiers

/// Audio file formats `PlaybackEngine.exportAudio(to:format:...)` can render
/// to. MP3 is deliberately not offered — AVFoundation (and Apple's own
/// `afconvert`) can only *decode* MP3, never encode it; a real encoder would
/// mean bundling a third-party library, the first non-Apple dependency
/// anywhere in this project. AAC/MP4 cover "a compact, widely-compatible
/// file" just as well as MP3 would.
enum AudioExportFormat: String, CaseIterable, Identifiable {
    case wav
    case aac
    case mp4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: return "WAV (uncompressed)"
        case .aac: return "AAC (.m4a)"
        case .mp4: return "MP4 (AAC audio)"
        }
    }

    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .aac: return "m4a"
        case .mp4: return "mp4"
        }
    }

    var contentType: UTType {
        switch self {
        case .wav: return .wav
        case .aac: return .mpeg4Audio
        case .mp4: return .mpeg4Movie // the UTI macOS registers for .mp4, audio-only or not
        }
    }
}
