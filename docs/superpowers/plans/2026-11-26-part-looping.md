# Part Looping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Loop a single part, as played, seamlessly, chosen from a third state on the loop button.

**Architecture:** `PlaybackScheduler` gains an optional loop range it wraps inside, with continuous timing. `PlaybackEngine` swaps `isLooping` for a `LoopMode`, tracks the looped part, and derives the range from `PlayOrder.timeline`. The loop button and `PartProgressView` show it.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing, AVFoundation (unchanged).

**Spec:** `docs/superpowers/specs/2026-11-26-part-looping-design.md`

## Global Constraints

- macOS 13 target; must compile under CI's Xcode 16 Swift as well as local Swift 6.4 — keep pure logic off SwiftUI views (they're main-actor there).
- Export always renders the tune once, regardless of loop mode.
- Loop icons: `repeat` (off / tune), `repeat.1` (part).

## Review Focus

1. Changing tempo mid-loop — the loop must stay on the same part, at the new length.
2. Muting a voice mid-loop (rebuild restarts the scheduler) — loop continues.
3. Scrubbing into another part while part-looping moves the loop there.
4. A tie or note sounding across the loop end — silenced at the wrap, never stuck.
5. One-part tune in part mode — behaves like a tune loop, no crash.

---

### Task 1: Scheduler loop wrap

**Files:** Modify `Sources/PipePlayer/Audio/PlaybackScheduler.swift`; Test `Tests/PipePlayerTests/PlaybackSchedulerLoopTests.swift` (create)

**Interfaces — Produces:**
- `PlaybackScheduler.start(events:from:loop: Range<TimeInterval>? = nil, onNoteOn:onNoteOff:onFinished:)` — with `loop`, never finishes; wraps.
- `static func loopSlice(_ events: [ScheduledMIDIEvent], _ loop: Range<TimeInterval>) -> [ScheduledMIDIEvent]` — events with `lower <= time < upper`, plus note-offs at exactly `upper`.
- `static func loopPass(_ pass: Int, slice: [ScheduledMIDIEvent], from startTime: TimeInterval, loop: Range<TimeInterval>) -> [(elapsed: TimeInterval, event: ScheduledMIDIEvent)]` — pass 0: slice events at/after `startTime`, elapsed `time - startTime`; pass k ≥ 1: every slice event, elapsed `(upper - startTime) + (k-1)·length + (time - lower)`.
- `static func loopedTime(elapsed: TimeInterval, from startTime: TimeInterval, loop: Range<TimeInterval>) -> TimeInterval` — tune time for the UI clock.

- [ ] Tests: `loopSliceKeepsNoteOffAtTheEndButNotNoteOn`, `firstPassStartsMidLoop` (start 1.0 in 0..<4 → elapsed values = time − 1), `laterPassesFollowWithoutAGap` (pass 1 first event elapsed == 3.0, pass 2 == 7.0 for range 0..<4 starting at 1.0), `loopedTimeWraps` (elapsed 0.5 → 1.5; elapsed 3.5 → 0.5; elapsed 7.5 → 0.5).
- [ ] Run `swift test --filter PlaybackSchedulerLoopTests` → fails (missing symbols).
- [ ] Implement; the thread walks passes 0, 1, 2…; between passes it sends note-off for anything it turned on and hasn't turned off.
- [ ] Run → passes. Commit.

### Task 2: Engine loop mode

**Files:** Modify `Sources/PipePlayer/Audio/PlaybackEngine.swift`; Test `Tests/PipePlayerTests/PlaybackEngineTests.swift`

**Interfaces — Consumes:** Task 1. **Produces:**
- `enum LoopMode { case off, tune, part }`; `@Published var loopMode: LoopMode` (replaces `isLooping`); `@Published private(set) var loopedPartIndex: Int?`
- `func cycleLoopMode()` — off → tune → part → off; entering part loops the part at `currentTime`.
- `var loopRange: Range<TimeInterval>?` — the looped part's span from `PlayOrder.timeline(of: voices[0].tune, tempo: tempo)`, nil unless `.part`.
- `seek(to:)` in part mode moves `loopedPartIndex` to the part containing the target. `play()` in part mode starts at the range's start when outside it. `startScheduler` passes `loopRange`; `tickUIProgress` uses `PlaybackScheduler.loopedTime` when a range is active. Changing mode while playing silences and restarts the scheduler from `currentTime`.

- [ ] Tests (two-part tune, 2 beats each, tempo 60): `loopButtonCyclesThroughThreeModes`; `partModeLoopsThePartAtThePlayhead` (seek 3 → cycle twice → `loopedPartIndex == 1`, `loopRange == 2..<4`); `seekingIntoAnotherPartMovesTheLoop`; `tempoChangeRescalesTheLoop` (tempo 120 → `loopRange == 1..<2`); `exportRestoresLoopModeAfterFinishing` (rename of existing test, `.part`).
- [ ] Run → fails. Implement. Run full suite → passes. Commit.

### Task 3: Loop button and progress bar

**Files:** Modify `Sources/PipePlayer/Views/TransportControlsView.swift`, `Sources/PipePlayer/Views/PartProgressView.swift`, `Sources/PipePlayer/Views/ContentView.swift`

**Interfaces — Consumes:** Task 2's `loopMode`, `loopedPartIndex`, `cycleLoopMode()`.

- [ ] Loop button: on when `loopMode != .off`, icon `repeat.1` in part mode, tap → `cycleLoopMode()`; help text names the current mode.
- [ ] `PartProgressView(loopedPartIndex: Int?)`: looped segment gets a 2pt accent outline and a `repeat` icon after its number; caption prefixed with the icon when the active part is the looped one.
- [ ] Build, package, launch; open Raigmore, verify by eye. Commit, push, check CI.
