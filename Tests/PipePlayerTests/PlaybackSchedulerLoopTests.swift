import Testing
import Foundation
@testable import PipePlayer

struct PlaybackSchedulerLoopTests {

    private func on(_ t: TimeInterval, _ note: UInt8 = 69) -> ScheduledMIDIEvent {
        ScheduledMIDIEvent(time: t, kind: .noteOn, note: note, velocity: 100)
    }
    private func off(_ t: TimeInterval, _ note: UInt8 = 69) -> ScheduledMIDIEvent {
        ScheduledMIDIEvent(time: t, kind: .noteOff, note: note, velocity: 0)
    }

    /// Two notes per second-long beat across 0..<6; the loop is 0..<4.
    private var events: [ScheduledMIDIEvent] {
        (0..<6).flatMap { [on(Double($0)), off(Double($0) + 1)] }.sorted { $0.time < $1.time }
    }

    @Test func loopSliceKeepsNoteOffAtTheEndButNotNoteOn() {
        let slice = PlaybackScheduler.loopSlice(events, 0..<4)
        #expect(slice.contains(off(4)))
        #expect(!slice.contains(on(4)))
        #expect(slice.allSatisfy { $0.time <= 4 })
        #expect(slice.first == on(0))
    }

    @Test func firstPassStartsMidLoop() {
        let slice = PlaybackScheduler.loopSlice(events, 0..<4)
        let pass = PlaybackScheduler.loopPass(0, slice: slice, from: 1, loop: 0..<4)
        #expect(pass.first?.elapsed == 0)
        #expect(pass.first { $0.event.kind == .noteOn }?.event == on(1))
        #expect(pass.allSatisfy { $0.elapsed == $0.event.time - 1 })
    }

    @Test func laterPassesFollowWithoutAGap() {
        let slice = PlaybackScheduler.loopSlice(events, 0..<4)
        let second = PlaybackScheduler.loopPass(1, slice: slice, from: 1, loop: 0..<4)
        let third = PlaybackScheduler.loopPass(2, slice: slice, from: 1, loop: 0..<4)
        #expect(second.first?.elapsed == 3)
        #expect(second.first { $0.event.kind == .noteOn }?.event == on(0))
        #expect(third.first?.elapsed == 7)
        #expect(second.count == slice.count)
    }

    @Test func loopedTimeWraps() {
        #expect(PlaybackScheduler.loopedTime(elapsed: 0.5, from: 1, loop: 0..<4) == 1.5)
        #expect(PlaybackScheduler.loopedTime(elapsed: 3.5, from: 1, loop: 0..<4) == 0.5)
        #expect(PlaybackScheduler.loopedTime(elapsed: 7.5, from: 1, loop: 0..<4) == 0.5)
    }

    /// Event times and part boundaries are summed separately, so they can
    /// disagree in the last bits (seen in Raigmore: a note-off 2e-14 past
    /// the part's end). That mustn't drop the part's last note-off or pull
    /// in the next part's first note-on.
    @Test func loopSliceToleratesRoundingAtTheEdges() {
        let events = [on(-1e-12, 60), on(1, 61), off(4 + 1e-12, 61), on(4 - 1e-12, 62)]
        let slice = PlaybackScheduler.loopSlice(events, 0..<4)
        #expect(slice.contains(on(-1e-12, 60)))
        #expect(slice.contains(off(4 + 1e-12, 61)))
        #expect(!slice.contains(on(4 - 1e-12, 62)))
    }

    /// Seam cleanup happens when the pass ends, not when its last event
    /// plays, so a note held into the seam isn't cut short.
    @Test func passEndIsTheSeam() {
        #expect(PlaybackScheduler.loopPassEnd(0, from: 1, loop: 0..<4) == 3)
        #expect(PlaybackScheduler.loopPassEnd(1, from: 1, loop: 0..<4) == 7)
    }
}
