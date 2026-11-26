# Part looping

## Why

Pick one part and have it repeat until stopped — for drilling a part while
learning it, or playing along with it over and over. Play-along is the
demanding case: the loop seam has to be seamless.

## Goals

- Loop a single part, as played: its repeat and both endings included.
- No gap or stutter where the loop wraps.
- Visible at a glance which part is looping.
- Works with tempo changes mid-loop (slow a part down while it repeats).

## Non-goals

- Looping arbitrary ranges or a span of several parts.
- Count-ins, or a set number of repetitions.
- Looping in exported audio (export always renders the tune once).

## Approaches

Picking the part:
- **Chosen — a third state on the existing loop button**: off → loop tune →
  loop part (Music's repeat-one pattern). Nothing new to learn.
- Right-click a segment → "Loop This Part": explicit but undiscoverable.
- A separate loop-part button: one more control, competing with tune loop.

Wrapping:
- **Chosen — the scheduler wraps itself**: at the part's end it carries on
  from the part's start, timing continuous. No gap.
- Seek back on reaching the end (reuse the tune loop's restart): simpler,
  but leaves a small, uneven pause each time round — enough to throw off
  playing along.

## Design

- `PlaybackEngine.isLooping: Bool` becomes `loopMode: off | tune | part`,
  plus `loopedPartIndex`. The loop button cycles the three states; icons
  `repeat` (off/tune) and `repeat.1` (part).
- Switching to part mode loops the part playing at that moment (or part 1
  when stopped at the start). Clicking another segment — or scrubbing into
  another part — while part-looping moves the loop to that part.
- The loop range comes from `PlayOrder.timeline` at the current tempo, so it
  matches what's heard and follows tempo changes.
- `PlaybackScheduler.start` takes an optional loop range. Reaching its end, it
  turns off any notes still sounding, then continues from the first event at
  the range's start with its clock offset by the range length. Note-offs at
  exactly the end are played; note-ons there belong to the next part.
- The UI clock (`currentTime`) wraps the same way, so the progress bar and
  scrubber follow the loop.
- Pressing play while part-looping and positioned outside the looped part
  starts at the part's start.
- The drone sustains across the wrap.

## Look

The looped segment gets an accent outline and the tune-loop's repeat icon
next to its number. The caption under the bar carries it too:

```
 [ 1 ] [ 2 ⟳ ] [ 3 ] [ 4 ]        ← segment 2 outlined
 ⟳ Part 2 of 4 (repeat, 2nd time)
```

## Left to the builder

Exact outline weight and icon size; how the loop button's help text reads in
each state.
