# Developing PipePlayer

Technical notes for building from source, working on the codebase, and
understanding how specific file-format quirks are handled. See
[README.md](README.md) for what the app does and how to use it.

## Requirements

- macOS 13 or later
- Swift 5.10+ toolchain (Xcode or standalone Command Line Tools both work —
  Xcode is not required to build or run this)

## Building & running

```bash
swift build              # debug build
swift test                # run the parser/expander unit tests
swift run PipePlayer       # run directly from Terminal
```

For a real double-clickable `.app` (proper bundle, icon slot, Gatekeeper-safe
ad-hoc signature) rather than a bare executable:

```bash
./package_app.sh
```

This builds a release binary and produces `dist/PipePlayer.app`. Copy it to
`/Applications` or `~/Applications` and launch normally. Re-run the script
any time after changing the code to refresh the bundle.

## CI & releases

Every push and PR to `main` runs `swift build` + `swift test` on macOS via
[GitHub Actions](.github/workflows/ci.yml).

To cut a release: push a tag matching `v*` (e.g. `git tag v1.1.0 && git push
origin v1.1.0`). [The release workflow](.github/workflows/release.yml) builds
`PipePlayer.app`, zips it, and publishes it to the repo's Releases page with
that version baked into the bundle's `CFBundleVersion`. It can also be run
manually (without a tag) via the Actions tab's "Run workflow" button, which
uploads the build as a workflow artifact instead of a release.

Released builds are ad-hoc signed, not notarized (no paid Apple Developer
account behind this project) — Gatekeeper will flag a fresh download the
first time it's opened. Right-click the app → Open once to get past that;
subsequent launches are normal.

Write the annotated tag message as real release notes — a plain-language
summary of what changed and why it matters, not a commit-log dump.
`generate_release_notes: true` still appends GitHub's own auto-generated
commit list underneath, which is fine as a supplement, not a replacement.

## Format notes

- `.bmw` files are supported wherever they use the same plain-text "tune
  code" grammar as `.bww` (true of essentially all Bagpipe Music Writer
  Gold-era exports, including several observed older/plainer header
  variants). Pre-Gold BMW-DOS binary files are a different, largely
  undocumented format and are explicitly rejected with a clear error rather
  than silently mis-parsed.
- Ornament/embellishment coverage is exact for the common ones (doublings,
  throws, grips, birls, taorluath, crunluath, strikes, single grace notes,
  and most of the piobaireachd vocabulary). A handful of very rare/regional
  tokens fall back to a single conservative grace note rather than a fully
  authoritative figure — the tune still loads and plays, just with a less
  precise ornament in that one spot. Grace notes borrow their time from the
  note they decorate rather than adding new, un-notated time (capped at half
  that note's own duration) — otherwise a heavily-ornamented tune plays back
  measurably slower than its stated tempo purely from accumulated grace-note
  overhead, confirmed against a real tune where it drifted from a stated
  90bpm to an effective ~84bpm.
- `TuneTempo`/ABC's `Q:` are read at the meter's own natural tempo-marking
  beat unit, same as standard notation everywhere: quarter note for simple
  time (2/4, 3/4, 4/4 — read flat, unscaled), half note for cut time (2/2,
  ×2), and the dotted quarter for compound time (6/8, 9/8, 12/8, ×1.5) —
  confirmed directly against a real cut-time reel and a real jig, both of
  which otherwise dragged well under their intended speed. The tempo field in
  the transport controls always shows the number as written in the file
  (e.g. 132 for a jig), even though actual playback runs at the scaled-up
  equivalent (198) — only BWW/BMW/ABC need this; MusicXML's `<sound tempo>`
  is always flat quarter-note bpm by spec regardless of written meter. Slow
  airs, laments, and songs (from BWW's "Y" record or ABC's `R:` field) are
  exempted from the compound-time ×1.5/×3 scaling — that convention is for
  danced-to compound tunes and doesn't apply to a free, rubato air just
  because it happens to be written in 6/8. When no tempo is stated at all,
  the tune type (march, strathspey, reel, hornpipe, jig) picks a sensible
  default instead of a single flat number for every dance.
- Strathspeys are pointed at playback, not played as written. Written
  strathspey rhythm is dot-cut (3:1) and its reverse, the Scotch snap;
  rendered literally it reads as a lazy swing. `PerformanceStyle` tightens
  each adjacent 3:1 pair to 5:1 just before events are built, so live
  playback, export, and the progress bar all hear the same thing. Pair
  totals are preserved, so the beat never moves. It never inserts silence
  between notes — a chanter can't stop sounding, and an earlier version
  that detached notes that way sounded wrong immediately.
- An ABC file can hold a whole set: several `X:` tunes back to back, each
  with its own header. They're combined into one playable tune, each at its
  own tempo (later tunes' durations are stretched relative to the first),
  so the tempo control scales the whole set together the way a band speeds
  up a medley. Each part keeps its own tune type (`R:`), so a strathspey
  followed by a reel is pointed as one and played straight as the other.
- ABC and BWW/BMW are single-voice only — the grammar itself has no notion of
  multiple simultaneous parts, so every file loads as one "Melody" voice.
  Multi-voice simultaneous playback (see below) is a MusicXML-only feature.
- MusicXML support reads every `<part>` as its own simultaneous voice (see
  above), each independently mutable. `<chord>`-tagged notes (extra pitches
  stacked on a single note within one part) are still skipped — that's a
  different mechanism from multiple parts and isn't something this app plays
  back. Grace notes are read as literal pitches, same as ABC; MusicXML has no
  equivalent of BWW's named ornament tokens. G/A notes (the only chanter
  pitches with both a low and a high register) are resolved by scanning each
  part for every distinct octave a letter is written at — when a file uses
  exactly two, the lower is treated as the low register and the higher as
  the high one, since a written octave number alone isn't a reliable signal
  across different exporters (confirmed against a real exporter whose
  "high" register collided numerically with this app's own low-register
  constant). `.mxl` archives are unpacked via the system `unzip` tool rather
  than a bundled ZIP library. Each voice's progress (repeats, section
  boundaries) is tracked independently from its own barline markup, so if a
  source file's voices aren't perfectly consistent about where sections
  start and end, voices can drift apart by a second or two over a long tune
  rather than staying sample-locked — a real but minor limitation, not
  something this app tries to force into sync by overriding one voice's
  timing with another's.
- Audio export renders offline (`AVAudioEngine`'s manual rendering mode)
  rather than recording a real-time playthrough — the same performance
  timing, computed as fast as the CPU can rather than throttled to real
  time, and nothing is audible while it runs since it never touches
  hardware output. Each render chunk is bounded by whichever comes first —
  the buffer's max size, or the next scheduled note event's exact frame
  position — rather than a fixed chunk size; grace notes as short as ~23ms
  can otherwise land entirely inside one fixed chunk alongside other notes,
  stacking their onsets together and clipping. MP3 isn't offered — Apple's
  frameworks can only decode MP3, never encode it, and adding a real encoder
  would mean bundling a third-party library, the one dependency this project
  has avoided everywhere else.

## Credits

- BWW/BMW grammar details (pitch letters, duration codes, dot markers, tie
  tokens, barline/repeat semantics) were cross-checked against
  [tomvodi/limepipes-plugin-bww](https://github.com/tomvodi/limepipes-plugin-bww)
  (MIT licensed), a real working open-source parser for this format.
- The embellishment-to-grace-note-sequence table was transcribed from
  [Ensemble](https://thisisensemble.com)'s own embellishment palettes rather
  than approximated from written tutor descriptions.
