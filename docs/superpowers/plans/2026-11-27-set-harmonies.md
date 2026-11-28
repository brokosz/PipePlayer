# Harmonies in Sets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tunes in a set carry harmonies saved in the `.pipeset`; a tune tab with harmonies can be saved as a one-tune set; harmonies get a visible remove button.

**Architecture:** `SetList.Entry` gains harmony references. `AppState.reloadSet` loads each entry's harmonies with `VoiceAligner.fit` into its segment, with voice ids unique per entry. Add/remove harmony route to the set entry when the tab holds a set. The engine exposes the current segment's voices for the mute row.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-27-set-lists-design.md` (Amendment section) and `docs/superpowers/specs/2026-11-26-add-harmony-design.md`

## Global Constraints

- macOS 13; CI's Xcode 16 Swift — pure logic off views.
- Old `.pipeset` files (no `harmonies` key) must still load.
- Mutes are session-only in set tabs; never written to the file.
- Commit straight to `main`; push only when the user asks.

## Review Focus

1. A harmony file missing when the set opens — tune still plays, harmony skipped quietly (listed with the problem).
2. Moving or removing a tune that has harmonies — its harmonies go with it.
3. Muting a harmony in tune 2, then crossing back into tune 1 — tune 1's voices unaffected; tune 2's mute kept on return.
4. Save as Set… from a tune tab — relative paths computed for the harmony files too.
5. Removing a harmony while playing in a set — playback continues at the same place.

---

### Task 1: Harmony references in the set file

**Files:** Modify `Sources/PipePlayer/Models/SetList.swift`; Test `Tests/PipePlayerTests/SetListTests.swift`

**Produces:**
- `struct SetList.FileRef: Codable, Equatable { var relativePath: String?; var bookmark: Data? }`
- `Entry.harmonies: [FileRef]` (decodes as `[]` when absent — custom `init(from:)`).
- `mutating func addHarmony(_ url: URL, toEntry id: UUID, relativeTo setURL: URL?)`, `mutating func removeHarmony(at index: Int, fromEntry id: UUID)`, `func url(for ref: FileRef, relativeTo setURL: URL?) -> URL?` (entry resolution reuses it); `rebase` also rewrites harmony paths.

- [ ] Tests: `oldFilesWithoutHarmoniesStillLoad` (JSON literal without the key), `harmoniesRoundTrip`, `rebaseRewritesHarmonyPaths`.
- [ ] Run → fails. Implement. Run full suite → passes. Commit "Set entries carry harmony files".

### Task 2: Harmonies in set mode

**Files:** Modify `Sources/PipePlayer/AppState.swift`, `Sources/PipePlayer/Audio/PlaybackEngine.swift`; Test `Tests/PipePlayerTests/AppStateTests.swift`, `PlaybackEngineTests.swift`

**Consumes:** Task 1. **Produces:**
- Engine: `var currentVoices: [Voice]` (voices of the segment at the playhead); `load(segments:)` keeps `mutedVoiceIDs` that still exist (instead of clearing) when called with `keepingMutes: true`.
- `reloadSet` builds each segment as melody voices + each harmony `Voice(id: "\(entry.id)-h\(i)-\(voice.id)", name: file name, tune: VoiceAligner.fit(…, to: melody))`; melody ids become `"\(entry.id)-\(voice.id)"`. A harmony that fails is skipped and noted in `entryProblems`.
- `addHarmony(urls:)` in a set attaches to the entry at the playhead; `addHarmony(urls:toEntry:)`; `removeHarmony(voiceID:)` in a set removes it from its entry; `isHarmony` works in sets; all write the file. `func harmonyNames(ofEntry:) -> [String]`.
- `func saveTuneAsSet(to url: URL) throws` — tune tab → one-tune set with its harmonies, saved, tab becomes the set.

- [ ] Tests: `addingHarmonyInASetAttachesToTheTuneAtThePlayhead`, `setHarmoniesAreSavedAndReloaded`, `removingASetHarmonyRemovesItFromTheFile`, `aMissingHarmonyDoesntStopTheTune`, `mutesSurviveASetReload`, `saveTuneAsSetKeepsItsHarmonies`, engine `currentVoicesFollowThePlayhead`.
- [ ] Run → fails. Implement. Run full suite → passes. Commit "Harmonies in sets; save a tune and its harmonies as a set".

### Task 3: UI

**Files:** Modify `ContentView.swift`, `SetListView.swift`, `VoiceMuteControlsView.swift`, `PipePlayerApp.swift`, `README.md`

- [ ] Voice row: shows `engine.currentVoices` (set tabs too) when > 1; each harmony gets a borderless × (`xmark.circle.fill`, help "Remove Harmony") after its checkbox; context menu kept.
- [ ] Set list: row context menu "Add Harmony…" (`chooseSetTuneFiles` → `addHarmony(urls:toEntry:)`); harmony names as a secondary line "+ Name" under the tune.
- [ ] Drop in a set tab: split shows **Add to Set** | **Add Harmony** (attaches to the playhead tune).
- [ ] Menu: Add Harmony… enabled in set tabs; File → Save as Set… enabled in a tune tab (save panel → `saveTuneAsSet`).
- [ ] README line. Build, package, install; user checks by eye. Commit.
