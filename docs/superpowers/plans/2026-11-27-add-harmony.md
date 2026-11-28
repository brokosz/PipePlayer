# Add Harmony Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add any tune file to the open tune as an extra voice, by menu or drop, aligned part by part to the melody and remembered per tab.

**Architecture:** A new part-by-part alignment in `VoiceAligner` fits a harmony tune to the melody's form. `AppState` keeps the added files and rebuilds `voices` (melody voices + aligned harmony voices) through the existing `engine.load(voices:)`, keeping tempo and mutes. `ContentView` gets the split drop target, the menu command, persistence and a Remove item on the mute row.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-26-add-harmony-design.md`

## Global Constraints

- macOS 13 target; must compile under CI's Xcode 16 Swift as well as local Swift 6.4 — keep pure logic off SwiftUI views (they're main-actor there).
- The first voice leads: tempo, repeats and part structure come from it.
- Menu: File → Add Harmony… (⌥⌘O), enabled only when a tune is open.
- Drop halves read **Open** and **Add as Harmony**; no split when no tune is open.
- Commit straight to `main`; push and check CI at the end.

## Review Focus

1. Adding a harmony mid-playback — playback restarts from the same position at the same tempo, existing mutes kept.
2. Adding the same file twice — second copy gets its own id, both mutable independently.
3. A harmony file that fails to parse — the error alert, the tab unchanged.
4. Opening a different tune in a tab with harmonies — harmonies cleared, not re-added on restore.
5. A harmony with more parts than the melody, or an empty part — no crash, extras dropped.

---

### Task 1: Part-by-part alignment

**Files:** Modify `Sources/PipePlayer/Music/VoiceAligner.swift`; Test `Tests/PipePlayerTests/VoiceAlignerTests.swift`

**Interfaces — Produces:**
- `static func fit(_ harmony: Tune, to melody: Tune) -> Tune` — returns `harmony` with exactly `min(harmony.parts.count, melody.parts.count)` parts; each part *i* takes melody part *i*'s `hasRepeat` and `rhythm`. Same bar count: each bar takes its melody bar's `endingNumbers` and is scaled to that bar's beats. Different bar count: endings cleared, every note scaled by (melody part's written beats ÷ harmony part's beats). `tempo` = melody's. Empty parts (0 beats) are left unscaled.

- [ ] Tests (build tunes inline, 1-beat quarter notes):
  - `fitTakesTheMelodysRepeats` — melody 2 parts × 4 bars, both `hasRepeat`; harmony same shape, no repeats → every fitted part `hasRepeat`.
  - `fitTakesTheMelodysEndings` — melody part with bars 3–4 marked `[1]`/`[2]`; harmony 4 bars unmarked → fitted bars carry `[1]`/`[2]`.
  - `fitScalesAMismatchedPartAsAWhole` — melody part 10 bars × 2 beats, harmony part 8 bars × 2 beats → fitted part sums to 20 beats, still 8 bars, endings empty.
  - `fitDropsExtraHarmonyParts` — melody 2 parts, harmony 3 → 2 parts.
  - `fitUsesTheMelodysTempo` — melody 69, harmony 90 → 69.
- [ ] Run `swift test --filter VoiceAlignerTests` → fails (no `fit`).
- [ ] Implement; leave `align(_:)` untouched (MusicXML multi-voice keeps today's behaviour).
- [ ] Run → passes. Commit "Fit a harmony tune to the melody part by part".

### Task 2: Harmony voices in AppState

**Files:** Modify `Sources/PipePlayer/AppState.swift`; Test `Tests/PipePlayerTests/AppStateTests.swift`

**Interfaces — Consumes:** Task 1 `VoiceAligner.fit`. **Produces:**
- `@Published private(set) var harmonyURLs: [URL]`
- `func addHarmony(urls: [URL])` — loads each with `TuneFileLoader.loadVoices`; every voice becomes `Voice(id: "harmony-\(n)-\(voiceID)", name: <file name without extension, plus " – \(voice.name)" when the file has several voices>, tune: VoiceAligner.fit(voice.tune, to: melody))`, `n` = position in `harmonyURLs`. Appends to `harmonyURLs` and reloads. A file that fails sets `errorMessage` and is skipped.
- `func removeHarmony(voiceID: String)` — removes the URL that voice came from (all its voices) and reloads.
- `func isHarmony(_ voiceID: String) -> Bool`
- Reload: `engine.load(voices: melodyVoices + harmonyVoices)`, then restores tempo, mutes still valid, `currentTime`, and resumes if it was playing. `open(url:)` clears `harmonyURLs`.

- [ ] Tests (write two small BWW files to a temp dir):
  - `addHarmonyAppendsAVoiceNamedAfterTheFile` — voices count 2, second named `"Tune - Seconds"`, `isHarmony` true.
  - `addingTheSameFileTwiceGivesDistinctIDs`.
  - `addHarmonyKeepsTempoAndMutes` — set tempo 70, mute melody, add → tempo 70, melody still muted.
  - `removeHarmonyRemovesItsVoices`.
  - `openingAnotherTuneClearsHarmonies`.
  - `aHarmonyThatFailsToParseLeavesVoicesAlone` — `errorMessage` set, voices count 1.
- [ ] Run → fails. Implement. Run full suite → passes. Commit "Add and remove harmony voices".

### Task 3: Menu, drop targets, mute row, persistence

**Files:** Modify `Sources/PipePlayer/PipePlayerApp.swift`, `Sources/PipePlayer/Views/ContentView.swift`, `Sources/PipePlayer/Views/VoiceMuteControlsView.swift`, `README.md`

**Interfaces — Consumes:** Task 2.

- [ ] Menu: "Add Harmony…" (⌥⌘O) after Open…, a view using `@FocusedObject var appState: AppState?` like `CloseTuneMenuCommand`, disabled when `appState?.tune == nil`, multi-select panel via `AppState.chooseTuneFiles()`.
- [ ] Drop: when `appState.tune != nil`, the highlight shows two halves (left **Open**, right **Add as Harmony**); the half under the pointer is emphasised and decides the action. Track location with `onDrop(of:delegate:)` (`DropDelegate.dropUpdated` gives `info.location`). No tune → today's single outline and open.
- [ ] Mute row: `.contextMenu { Button("Remove Harmony") }` on toggles where `isHarmony`; pass `appState` (or a remove closure) into `VoiceMuteControlsView`.
- [ ] Persistence: `@SceneStorage("PipePlayer.harmonyBookmarks") var savedHarmonies: Data` holding a property-list `[Data]` of bookmarks; written on `harmonyURLs` change; restored after the tune restores (before `applySavedPlaybackSettings`, so harmony mutes come back). Unresolvable bookmarks are skipped silently.
- [ ] README: one paragraph under the tabs/looping docs.
- [ ] Build, `./package_app.sh`, install to `~/Applications`; open `Cullen Bay.bww`, drop `Cullen Bay - Seconds.bww` on the right half, play through both repeats, mute each, quit and relaunch → harmony back. Commit, push, check CI.
