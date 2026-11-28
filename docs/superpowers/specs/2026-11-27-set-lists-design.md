# Set lists

## Why

To run competition sets (MSR, TLM) start to finish, or to hear how two
jigs or three reels sit together. The joins are the point: the next tune
comes in on the next beat, no pause.

## Goals

- An ordered list of tunes that plays straight through, each tune once.
- Seamless joins, each tune at its own tempo.
- The list visible in the main window, with + and − to add and remove
  tunes — only in a tab that holds a set.
- Saved as a file that lives next to the tunes.

## Non-goals

- Playing a tune more than once before moving on.
- Count-ins, gaps or crossfades between tunes.

## Approaches

The join:
- **Chosen — one combined timeline.** The set is built into one long event
  list, tune after tune, each at its own tempo, and played by the existing
  scheduler in one go — the same mechanism that made the part-loop seam
  gap-free. Scrub, export and looping work across the set unchanged.
- Load the next tune when one finishes: simpler, but a handoff on the beat
  where any latency is audible.

Where a set lives:
- **Chosen — a set file** (`MSR.pipeset`), opened in a tab like a tune:
  Open Recent, Finder, drag-and-drop and tab restore all apply.
- An in-app library sidebar: more UI, and sets can't travel with the tunes.

## Design

- **File:** JSON — a name, and per tune: its path relative to the set file,
  a bookmark as fallback, and an optional tempo. `.pipeset` is registered as
  a document type PipePlayer opens.
- **Making one:** File → New Set (⇧⌘N) opens a new tab with an empty set.
  Edits save to the file automatically once it has one; ⌘S on an untitled
  set asks where. An untitled set survives tab restore (contents kept in
  the tab's scene storage).
- **The list:** shown only in a set tab, between the header and the
  progress bar. One row per tune: number, title, tempo. The playing tune is
  highlighted; clicking a row seeks to that tune's start; rows drag to
  reorder. **+** opens a multi-select file picker and appends; **−** removes
  the selected row. Dropping tune files on a set tab appends them (no
  Open/Add as Harmony split there).
- **Playback:** each tune is loaded and expanded as today, its events built
  at its own tempo, and offset to start where the previous tune's events end.
  A tune whose file is missing or fails to parse shows greyed in the list
  with the reason, and is skipped.
- **Part timeline:** built per tune at that tune's tempo and offset the same
  way, so the progress bar, seeking and part loop line up with the audio.
- **Voices:** each tune plays all its own voices; the voice mute row is
  hidden in a set tab (voice ids aren't shared between tunes). *Builder's
  call.*
- **Tempo:** the tempo field shows and changes the tempo of the tune at the
  playhead (playing or stopped); the
  change is stored with that tune in the set. Tunes without a stored tempo
  use their file's.
- **Progress bar:** a row of tune titles above the part segments, each
  spanning its tune's parts; part segments work as now across the set.
- **Loop:** tune loop repeats the whole set; part loop works on any part of
  any tune.
- **Window title:** the set name, with the playing tune's title under it.

## Left to the builder

List styling and row height; whether the list scrolls or the window grows;
the exact JSON keys.

## Amendment (2026-11-27): harmonies in sets

Reverses the original non-goal. Any tune in a set can carry harmonies, and
the set remembers them — for a one-tune "pairing" (melody + seconds saved
together) as much as a TLM.

- **File:** each entry gains `harmonies` — each a relative path + bookmark,
  same as tunes. Files without the key still open.
- **Pairing:** in a tune tab with harmonies, File → Save as Set… saves a
  one-tune set with them; the tab becomes that set.
- **Adding in a set:** right-click a row → Add Harmony…; the Add Harmony
  menu item and the right half of a drop attach to the tune at the playhead.
  Harmony names are listed under their tune's row.
- **Mute and remove:** the voice row shows in set tabs, for the tune at the
  playhead. Each harmony has a checkbox to mute it and a visible × to remove
  it (single-tune tabs too; right-click still works). Removing in a set
  removes it from the file.
- **Mutes aren't saved in the file:** they last for the tab's session.

