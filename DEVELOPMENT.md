# Developing PipePlayer

Building from source, working on the code, and how specific file-format
quirks are handled. For what the app does, see [README.md](README.md).

## Requirements

- macOS 13 or later
- Swift 5.10+ toolchain. Xcode or the standalone Command Line Tools both
  work; Xcode isn't required

## Building & running

```bash
swift build              # debug build
swift test               # parser/expander unit tests
swift run PipePlayer     # run from Terminal
```

To build a proper `.app` bundle (icon slot, ad-hoc signature) instead of a
bare executable:

```bash
./package_app.sh
```

This produces a release build at `dist/PipePlayer.app`. Copy it to
`/Applications` or `~/Applications`. Re-run after code changes.

## CI & releases

Every push and PR to `main` runs `swift build` and `swift test` on macOS via
[GitHub Actions](.github/workflows/ci.yml).

To cut a release, push a `v*` tag (`git tag v1.1.0 && git push origin
v1.1.0`). [The release workflow](.github/workflows/release.yml) builds
`PipePlayer.app`, zips it, and publishes it to Releases with the tag version
set as `CFBundleVersion`. Running the workflow manually from the Actions tab
uploads the build as a workflow artifact instead.

Releases are ad-hoc signed and not notarized, since there's no paid Apple
Developer account behind this. Gatekeeper flags a fresh download on first
launch; Control-click → Open gets past it once.

Write the annotated tag message as release notes: what changed and why it
matters, in plain language. `generate_release_notes: true` appends GitHub's
commit list below it, which is fine as an extra.

## Format notes

### BMW files

`.bmw` files are supported when they use the same plain-text tune-code
grammar as `.bww`. That covers nearly all Bagpipe Music Writer Gold-era
exports, including some older header variants. Pre-Gold BMW-DOS binary
files are a different, mostly undocumented format and are rejected with an
error instead of being mis-parsed.

### Parts, repeats and endings

Parts follow the file's own structure markers, never its layout. The specs
these were checked against: the
[BWW format spec](https://github.com/andyrblank/bww-format-spec),
[ABC 2.1](https://abcnotation.com/wiki/abc:standard:v2.1/), and
[MusicXML](https://musicxml.formats.music).

- BWW: `''!I` ends a repeat, `!I` ends a part, and `I!''`/`I!` start a
  repeat. `!`, `!!` and anything ending in `t` are barlines; a staff line
  break means nothing musically, and a part routinely runs across several
  lines. `'1`, `'2`, `'22`–`'28` and `'224` are endings (first digit = the
  time it's played); `'si`, `'do`, `'bis` and `'intro` brackets don't
  affect playback.
- Where real files bend those rules, the reading that keeps their intent
  wins (each case was found in the ~16,800-file collection the parser was
  checked against):
  - `!I` inside a repeat that a later `''!I` closes is a heavy barline at
    a staff line's end, not a part end. So is a bare `I!` inside an open
    repeat.
  - A repeat with no `''!I` repeats if it opened with dots (`I!''`); a
    bare `I! ... !I` is a part written out once. A `''!I` with no start
    repeats from the start of its part.
  - A pickup (up to one bar) written before the repeat sign stays with its
    part but plays the first time only.
  - A second ending with no first ending in its part is ignored. A first
    ending closed by `!I` still repeats once its second ending follows.
- An ending can start mid-bar in real files (Raigmore: `gg LAr_8 gbr LAl_8
  '1 gg LAr_8 El_8`). The spec says an ending written after a note starts
  with the next bar, but taken literally that leaves Raigmore's first
  ending empty. The bar is split at the marker instead, so its common half
  plays on both passes.
- A second ending written after the repeat sign (`''!I '2 ...`, or a
  MusicXML backward repeat followed by `<ending number="2">`) belongs to
  the repeated part (`Tune.attachingTrailingEndings`). A part with no
  repeat plays every measure; an ending marker there never silences music.
- ABC's header `P:` play order (`P:AABB`) isn't applied yet; parts play in
  the order written.
- `PlayOrder` is the single walk of the play order. `MIDIEventBuilder`
  schedules audio from it and `PartProgressView` draws from it, so the
  progress bar can't drift from what's heard. Segments are sized by
  written length (both endings counted once) and fill once per pass.

### Ornaments

The common embellishments are exact: doublings, throws, grips, birls,
taorluath, crunluath, strikes, single grace notes, and most of the
piobaireachd vocabulary. A few rare or regional tokens fall back to a
single grace note. The tune still plays, with a less accurate ornament in
that spot.

Grace notes take their time from the note they decorate, capped at half
that note's duration. Adding time instead made heavily ornamented tunes
drift slow; one tune marked 90bpm was playing at about 84.

### Tempo

`TuneTempo` and ABC's `Q:` are read in the meter's usual beat unit: quarter
note for simple time (2/4, 3/4, 4/4, unscaled), half note for cut time
(2/2, ×2), dotted quarter for compound time (6/8, 9/8, 12/8, ×1.5). Without
this, cut-time reels and jigs played well under speed.

The transport's tempo field shows the number as written (132 for a jig)
while playback runs at the scaled value (198). This applies only to
BWW/BMW/ABC. MusicXML's `<sound tempo>` is always quarter-note bpm per spec.

Slow airs, laments, and songs (BWW's "Y" record or ABC's `R:` field) skip
the compound-time scaling. That convention is for dance tunes, and an air in
6/8 shouldn't be sped up for it. With no stated tempo, the tune type
(march, strathspey, reel, hornpipe, jig) picks a default.

### Strathspey pointing

Written strathspey rhythm is dot-cut (3:1) and its reverse, the Scotch
snap. Played literally it sounds lazy. `PerformanceStyle` tightens each
adjacent 3:1 pair to 5:1 right before events are built, so live playback,
export, and the progress bar all agree. Pair totals are preserved, so the
beat doesn't move. It never inserts silence between notes. A chanter can't
stop sounding, and an earlier version that detached notes sounded wrong
immediately.

### ABC sets

An ABC file can hold several `X:` tunes back to back, each with its own
header. They're combined into one playable tune. Each keeps its own tempo
(later tunes' durations are stretched relative to the first), so the tempo
control scales the whole set together, like a band speeding up a medley.
Each part keeps its own `R:` tune type, so a strathspey followed by a reel
gets pointed and then played straight.

### Voices

ABC and BWW/BMW are single-voice. The grammars have no concept of
simultaneous parts, so every file loads as one "Melody" voice. A
MusicXML file can carry several.

Band seconds for BWW tunes live in their own files, so Add Harmony loads
another file as extra voices. `VoiceAligner.fit` fits it to the melody part
by part: tempo, repeats and endings come from the melody (seconds files
often omit repeats and state their own tempo), and a part with a different
bar count is scaled as a whole so it can't shift later parts. Harmony that
lives inside a single BWW file ("3rd line = seconds for 2nd line") is prose
and isn't attempted.

### Sets

A `.pipeset` file (JSON, `SetList`) lists tunes by path relative to the
set file, with a bookmark as fallback and an optional per-tune tempo.

`PlaybackEngine` plays a list of `PlaybackSegment`s (voices + tempo); a
single tune is a list of one. Events and the part timeline are built per
segment and laid end to end: segment *k+1* starts at segment *k*'s last
part end, so the scheduler plays a set as one gap-free run, and scrubbing,
looping and export work across it. `tempo` is the tempo of the segment at
the playhead; changing it rescales only that segment.

### MusicXML

Every `<part>` is its own simultaneous, mutable voice. `<chord>` notes
(stacked pitches within one part) are skipped; that's a different mechanism
and not something the app plays. Grace notes are read as literal pitches,
same as ABC, since MusicXML has nothing like BWW's named ornament tokens.

G and A are the only chanter pitches with low and high registers. They're
resolved by collecting every octave each letter is written at within a
part. If there are exactly two, the lower is low G/A and the higher is
high. Octave numbers alone aren't reliable across exporters; one exporter's
"high" register collided with this app's low-register constant.

`.mxl` archives are unpacked with the system `unzip` instead of a bundled
ZIP library.

Each voice tracks repeats and section boundaries from its own barlines. If
a file's voices disagree about where sections start and end, they can drift
apart by a second or two over a long tune. The app doesn't override one
voice's timing with another's to force sync.

### Audio export

Export renders offline using `AVAudioEngine`'s manual rendering mode
instead of recording a live playthrough. Timing is identical, it runs as
fast as the CPU allows, and nothing plays through the speakers.

Each render chunk ends at the buffer's max size or the next note event's
exact frame, whichever comes first. With fixed chunk sizes, grace notes as
short as ~23ms could land in the same chunk as other notes, stacking their
onsets and clipping.

MP3 isn't offered. Apple's frameworks decode MP3 but can't encode it, and a
third-party encoder would be the project's only dependency.

## Credits

- BWW/BMW grammar details (pitch letters, duration codes, dots, ties,
  barline/repeat semantics) were cross-checked against
  [tomvodi/limepipes-plugin-bww](https://github.com/tomvodi/limepipes-plugin-bww)
  (MIT), an open-source parser for the format.
- The embellishment-to-grace-note table was transcribed from
  [Ensemble](https://thisisensemble.com)'s embellishment palettes.
