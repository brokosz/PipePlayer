# Add harmony

## Why

BWW has no second voice, so band seconds live in their own files
(`Cullen Bay - Seconds.bww`, the Steam Train to Mallaig piper 3/4 files —
16 in the collection). Playing a tune with its seconds underneath, and
muting either side, is how you practise either line against the other.

## Goals

- Add any tune file to the open tune as one more voice, by drop or menu.
- More than one (piper 3 and piper 4).
- The added voice plays with the melody: same tempo, same repeats.
- Remembered when the tab is restored.

## Non-goals

- Reading harmony out of a single BWW file (Classical Bob's "3rd line =
  seconds for 2nd line" is prose; it can't be parsed reliably).
- "Play only second time through" and similar written instructions.

## Approaches

Telling "add" from "open" on a drop:
- **Chosen — two drop targets.** With a tune open, dragging a file over the
  window splits the highlight into **Open** and **Add as Harmony** halves.
- ⌥-drop adds: quick, but hidden.
- Guess from the filename ("seconds", "harmony"): misses `72NDS.bww`.

## Design

- **Commands:** File → Add Harmony… (⌥⌘O), enabled when a tune is open;
  a multi-select open panel. Dropping on the Add half does the same. With
  no tune open, drops open as today (no split).
- **Voices:** each added file's voices join after the current ones, named
  after the file ("Cullen Bay - Seconds"), with ids unique within the tab
  so mutes persist. They appear in the existing voice mute row, which gains
  a Remove Harmony context-menu item on added voices.
- **Following the melody:** the first voice leads. Tempo comes from the
  melody (Loch Rannoch's seconds say 90 against the melody's 69). Alignment
  goes part by part — harmony part *i* against melody part *i*:
  - Same bar count: the harmony part takes the melody part's repeat and
    ending numbers, then each bar is scaled to its melody bar (as
    `VoiceAligner` does now). Cullen Bay's unrepeated seconds then play both
    times.
  - Different bar count (Highland Cradle Song, 10/9 against 8/8): the part
    takes the melody's repeat and is scaled as a whole to the melody part's
    length, so the mismatch can't spill into later parts.
  - Extra harmony parts are dropped; missing ones are silent.
  MusicXML files that already carry several voices keep their current
  behaviour.
- **Persistence:** the added files' bookmarks are stored per tab next to
  the tune's; restoring re-adds them. Opening a different tune in the tab
  clears them.
- Progress bar, part looping and export are unchanged; they already work
  from the first voice and the combined events.

## Left to the builder

Drop-target styling; exact id scheme; how a file that fails to parse is
reported (same alert as opening).
