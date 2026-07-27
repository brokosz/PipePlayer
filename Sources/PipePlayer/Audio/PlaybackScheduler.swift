import Foundation

/// A precise event-list clock: given a flat, time-sorted list of note on/off
/// events, fires each one at (approximately) the right wall-clock moment.
///
/// This deliberately does NOT use `DispatchQueue.asyncAfter` (an earlier
/// version did). Measured directly against a real ~93-second tune, GCD's
/// `asyncAfter` let events run up to **6 seconds** late, non-monotonically
/// (drifting late, then partly catching up, then drifting late again) —
/// consistent with GCD's documented default timer leeway/coalescing, where
/// the system is explicitly permitted to slip a deadline by a fraction of
/// how far out it is to batch wake-ups for power efficiency. That's the
/// right tradeoff for background work; it's wrong for music timing spanning
/// tens of seconds to minutes.
///
/// Instead, a single dedicated thread polls a sorted cursor against
/// `mach`-backed wall-clock time in ~2ms steps and fires each event the
/// moment its deadline has passed, with no timer-coalescing layer in the
/// way. This one clock drives both the local sampler and MIDI-out via the
/// same callbacks, so the two outputs never fall out of sync with each other.
/// `@unchecked Sendable`: `generation` is the only mutable state, and every
/// access to it goes through `lock`.
final class PlaybackScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func start(
        events: [ScheduledMIDIEvent],
        from startTime: TimeInterval,
        onNoteOn: @escaping @Sendable (UInt8, UInt8) -> Void,
        onNoteOff: @escaping @Sendable (UInt8) -> Void,
        onFinished: @escaping @Sendable () -> Void
    ) {
        stop()
        let pending = events.filter { $0.time >= startTime }
        guard !pending.isEmpty else {
            onFinished()
            return
        }

        let myGeneration: Int = {
            lock.lock()
            defer { lock.unlock() }
            return generation
        }()

        let thread = Thread { [weak self] in
            let anchor = Date()
            var index = 0
            while index < pending.count {
                guard let self, self.isCurrent(myGeneration) else { return }
                let event = pending[index]
                let targetElapsed = event.time - startTime
                let elapsed = Date().timeIntervalSince(anchor)
                let remaining = targetElapsed - elapsed
                if remaining > 0.002 {
                    Thread.sleep(forTimeInterval: min(remaining, 0.002))
                    continue
                }
                switch event.kind {
                case .noteOn: onNoteOn(event.note, event.velocity)
                case .noteOff: onNoteOff(event.note)
                }
                index += 1
            }
            if let self, self.isCurrent(myGeneration) {
                onFinished()
            }
        }
        thread.name = "com.pipeplayer.scheduler"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        thread.start()
    }

    private func isCurrent(_ generationToCheck: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generationToCheck == generation
    }

    /// Invalidates any in-flight scheduler thread (it checks `isCurrent` each
    /// loop iteration and exits within ~2ms) rather than tracking/cancelling
    /// the `Thread` object directly.
    func stop() {
        lock.lock()
        generation += 1
        lock.unlock()
    }
}
