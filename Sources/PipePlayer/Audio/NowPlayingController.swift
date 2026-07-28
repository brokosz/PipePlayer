import Foundation
import MediaPlayer
import Combine

/// Publishes now-playing metadata and responds to hardware media keys
/// (F7/F8/F9, or a keyboard's dedicated ⏮/⏯/⏭ row) via the standard
/// `MediaPlayer` remote-command framework — the sanctioned way for a macOS
/// app to receive these key presses, no private APIs or entitlements
/// involved. macOS routes hardware media keys to whichever app currently
/// has now-playing info published, so keeping `MPNowPlayingInfoCenter` in
/// sync with playback state isn't just informational — it's what makes the
/// keys reach this app at all.
///
/// There's no multi-track concept to skip between (one tune at a time), so
/// the previous/next keys (F7/F9) seek the current tune back/forward by 10
/// seconds instead of switching files — the same convention single-episode
/// media apps (podcasts, audiobooks) commonly use for those keys.
@MainActor
final class NowPlayingController {
    private weak var engine: PlaybackEngine?
    private var cancellables: Set<AnyCancellable> = []

    private static let seekSkipInterval: TimeInterval = 10

    init(engine: PlaybackEngine) {
        self.engine = engine
        configureCommands()
        observeEngine()
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            engine.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            engine.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            if engine.state == .playing { engine.pause() } else { engine.play() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            engine.stop()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            engine.seek(to: engine.currentTime - Self.seekSkipInterval)
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let engine = self.engine else { return .commandFailed }
            engine.seek(to: engine.currentTime + Self.seekSkipInterval)
            return .success
        }
    }

    private func observeEngine() {
        guard let engine else { return }
        Publishers.CombineLatest4(engine.$state, engine.$currentTime, engine.$duration, engine.$voices)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, currentTime, duration, voices in
                self?.publishNowPlayingInfo(state: state, currentTime: currentTime, duration: duration, voices: voices)
            }
            .store(in: &cancellables)
    }

    private func publishNowPlayingInfo(state: PlaybackState, currentTime: TimeInterval, duration: TimeInterval, voices: [Voice]) {
        let center = MPNowPlayingInfoCenter.default()
        guard let title = voices.first?.tune.title else {
            center.nowPlayingInfo = nil
            center.playbackState = .unknown
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        if let composer = voices.first?.tune.composer, !composer.isEmpty {
            info[MPMediaItemPropertyArtist] = composer
        }
        center.nowPlayingInfo = info
        // Separate from the dictionary above — macOS uses this to decide
        // whether this app is a legitimate "now playing" candidate that
        // hardware media keys should route to at all. Leaving it at the
        // default `.unknown` was the likely reason the keys didn't reliably
        // do anything.
        switch state {
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        case .stopped: center.playbackState = .stopped
        }
    }
}
