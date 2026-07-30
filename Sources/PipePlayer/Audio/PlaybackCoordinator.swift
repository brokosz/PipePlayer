import Foundation

/// Ensures only one tune is ever audibly playing at once across every open
/// window/tab. Each window owns its own independent `PlaybackEngine` (so
/// switching tabs never interrupts whatever tab is currently playing — the
/// engine itself keeps running in the background), but starting playback in
/// one tab should stop whichever *other* tab was playing, the same way a
/// single-output audio app behaves when more than one document is open.
///
/// Not actor-isolated, matching `PlaybackEngine`'s own approach: every call
/// site (SwiftUI transport buttons, media-key remote commands) is already on
/// the main thread by convention, just not provably so to the compiler.
final class PlaybackCoordinator: @unchecked Sendable {
    static let shared = PlaybackCoordinator()

    private weak var activeEngine: PlaybackEngine?

    private init() {}

    func willStartPlaying(_ engine: PlaybackEngine) {
        if let activeEngine, activeEngine !== engine {
            activeEngine.stop()
        }
        activeEngine = engine
    }

    func stoppedPlaying(_ engine: PlaybackEngine) {
        if activeEngine === engine {
            activeEngine = nil
        }
    }
}
