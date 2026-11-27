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

    /// - Parameter loop: when set, play to the range's end and carry on
    ///   from its start, forever (until `stop`), with no gap at the seam:
    ///   each pass is timed from the same anchor, so the wrap costs nothing.
    func start(
        events: [ScheduledMIDIEvent],
        from startTime: TimeInterval,
        loop: Range<TimeInterval>? = nil,
        onNoteOn: @escaping @Sendable (UInt8, UInt8, UInt8) -> Void, // note, velocity, channel
        onNoteOff: @escaping @Sendable (UInt8, UInt8) -> Void, // note, channel
        onFinished: @escaping @Sendable () -> Void
    ) {
        stop()
        let slice = loop.map { Self.loopSlice(events, $0) } ?? []
        let isLooping = (loop.map { !$0.isEmpty } ?? false) && !slice.isEmpty
        let pending = isLooping ? [] : events.filter { $0.time >= startTime }
        guard isLooping || !pending.isEmpty else {
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
            // Plays one list of (elapsed, event) against the shared anchor;
            // false if stopped partway.
            func play(_ timed: [(elapsed: TimeInterval, event: ScheduledMIDIEvent)], sounding: inout Set<[UInt8]>) -> Bool {
                var index = 0
                while index < timed.count {
                    guard let self, self.isCurrent(myGeneration) else { return false }
                    let (targetElapsed, event) = timed[index]
                    let remaining = targetElapsed - Date().timeIntervalSince(anchor)
                    if remaining > 0.002 {
                        Thread.sleep(forTimeInterval: min(remaining, 0.002))
                        continue
                    }
                    switch event.kind {
                    case .noteOn:
                        onNoteOn(event.note, event.velocity, event.channel)
                        sounding.insert([event.note, event.channel])
                    case .noteOff:
                        onNoteOff(event.note, event.channel)
                        sounding.remove([event.note, event.channel])
                    }
                    index += 1
                }
                return true
            }

            var sounding: Set<[UInt8]> = []
            if let loop, isLooping {
                var pass = 0
                while play(Self.loopPass(pass, slice: slice, from: startTime, loop: loop), sounding: &sounding) {
                    // Hold until the seam itself — the pass's last event can
                    // come well before it — then turn off anything still on
                    // (a tie running past the part's end), which would
                    // otherwise hang across the wrap.
                    let seam = Self.loopPassEnd(pass, from: startTime, loop: loop)
                    while true {
                        guard let self, self.isCurrent(myGeneration) else { return }
                        let remaining = seam - Date().timeIntervalSince(anchor)
                        if remaining <= 0.002 { break }
                        Thread.sleep(forTimeInterval: min(remaining, 0.002))
                    }
                    for key in sounding { onNoteOff(key[0], key[1]) }
                    sounding.removeAll()
                    pass += 1
                }
                return
            }
            let timed = pending.map { (elapsed: $0.time - startTime, event: $0) }
            if play(timed, sounding: &sounding), let self, self.isCurrent(myGeneration) {
                onFinished()
            }
        }
        thread.name = "com.pipeplayer.scheduler"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        thread.start()
    }

    // MARK: - Loop arithmetic

    /// The events one time round `loop` plays: everything starting inside
    /// it, plus note-offs landing exactly on its end (a note-on there
    /// belongs to whatever follows).
    ///
    /// Event times and part boundaries are summed separately and can
    /// disagree in the last bits, so the edges are compared with a small
    /// tolerance — far below anything audible.
    static func loopSlice(_ events: [ScheduledMIDIEvent], _ loop: Range<TimeInterval>) -> [ScheduledMIDIEvent] {
        let lower = loop.lowerBound - edgeTolerance
        let upper = loop.upperBound - edgeTolerance
        return events.filter { event in
            (event.time >= lower && event.time < upper)
                || (event.kind == .noteOff && abs(event.time - loop.upperBound) <= edgeTolerance)
        }
    }

    static let edgeTolerance: TimeInterval = 1e-6

    /// When pass `pass` reaches the loop's end, in seconds since starting.
    static func loopPassEnd(_ pass: Int, from startTime: TimeInterval, loop: Range<TimeInterval>) -> TimeInterval {
        (loop.upperBound - startTime) + Double(pass) * (loop.upperBound - loop.lowerBound)
    }

    /// One time round the loop, timed from the moment playback started.
    /// Pass 0 begins at `startTime` (possibly mid-loop); every later pass
    /// is the whole slice, following on with no gap.
    static func loopPass(
        _ pass: Int,
        slice: [ScheduledMIDIEvent],
        from startTime: TimeInterval,
        loop: Range<TimeInterval>
    ) -> [(elapsed: TimeInterval, event: ScheduledMIDIEvent)] {
        if pass == 0 {
            return slice.filter { $0.time >= startTime - edgeTolerance }.map { (max(0, $0.time - startTime), $0) }
        }
        let length = loop.upperBound - loop.lowerBound
        let passStart = (loop.upperBound - startTime) + Double(pass - 1) * length
        return slice.map { (passStart + ($0.time - loop.lowerBound), $0) }
    }

    /// Where in the tune playback is, `elapsed` seconds after starting at
    /// `startTime` inside `loop` — for the UI clock, which has to wrap with
    /// the audio.
    static func loopedTime(elapsed: TimeInterval, from startTime: TimeInterval, loop: Range<TimeInterval>) -> TimeInterval {
        let length = loop.upperBound - loop.lowerBound
        let time = startTime + elapsed
        guard length > 0, time >= loop.upperBound else { return time }
        return loop.lowerBound + (time - loop.upperBound).truncatingRemainder(dividingBy: length)
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
