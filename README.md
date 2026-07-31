# PipePlayer

A simple macOS app for playing back Great Highland Bagpipe tune files —
`.abc`, `.bww`, `.bmw`, `.musicxml`/`.xml`, and `.mxl` — with standard
transport controls and a choice of sound sources.

## Features

- Parses ABC notation, the BWW/BMW "tune code" text format shared by
  Bagpipe Music Writer, Bagpipe Musicworks Gold, and Bagpipe Reader, and
  MusicXML (plain `.musicxml`/`.xml` or compressed `.mxl`)
- MusicXML files with multiple `<part>`s (a harmony arrangement — melody plus
  harmony voices meant to sound together) play all of them back
  simultaneously, with one mute checkbox per voice so you can solo or drop
  any of them
- Full grace-note/embellishment expansion (doublings, throws, grips,
  taorluath, birl, strikes, crunluath, and the wider piobaireachd vocabulary)
  using ground-truth grace-note sequences, not approximated ones — grace
  notes borrow their time from the note they decorate rather than adding new,
  un-notated time, so a heavily-ornamented tune still plays at its stated
  tempo
- Multiple tunes can be open at once as native macOS window tabs, each with
  fully independent playback state — switching tabs never interrupts
  whichever one is playing, but starting playback in a different tab stops
  it, so only one tune is ever audibly playing at a time. The currently
  playing tab's title shows a 🔊 next to the tune name
- Transport controls: play/pause/stop, seek, tempo (numeric field + stepper,
  20–248bpm), volume, loop, and an optional continuous drone (needs a
  soundfont with a drone sample)
- Click a segment of the part-progress bar to jump straight to that part's
  start
- Tune type (march, strathspey, reel, hornpipe, jig) drives a sensible
  default tempo when a file doesn't specify one itself; slow airs and
  laments are recognized separately and exempted from the compound-time
  "beat = dotted quarter" scaling dance tunes need, so a 6/8 air doesn't play
  back inflated
- Three interchangeable sound sources:
  - Apple's built-in General MIDI bank (all 128 instruments, not just
    Bagpipe)
  - Any user-supplied SoundFont (`.sf2`) or DLS file
  - Any installed Audio Unit instrument (MainStage patches, Kontakt, or any
    other Music Device AU registered on the system), including its own
    plugin UI for browsing patches
- MIDI output via a virtual CoreMIDI port ("PipePlayer"), so the same tune
  can drive an external synth, DAW, or hardware module — independent of
  whether local audio is also playing
- File menu with Open, Open Recent, and Close Tune; drag-and-drop also
  supported

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

## Data & privacy

PipePlayer does not collect, transmit, or store any data anywhere. It only
reads the tune file you explicitly open (or drag onto the window) and plays
it locally through your Mac's audio output and/or the CoreMIDI system. There
is no network access, no analytics, no account, and nothing leaves your
machine. The only persisted state is a local "recent files" list (just file
paths, stored via `UserDefaults`) so File → Open Recent works across launches.

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
  precise ornament in that one spot.
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
- ABC and BWW/BMW are single-voice only — the grammar itself has no notion of
  multiple simultaneous parts, so every file loads as one "Melody" voice.
  Multi-voice simultaneous playback (see below) is a MusicXML-only feature.
- MusicXML support reads every `<part>` as its own simultaneous voice (see
  above), each independently mutable. `<chord>`-tagged notes (extra pitches
  stacked on a single note within one part) are still skipped — that's a
  different mechanism from multiple parts and isn't something this app plays
  back. Grace notes are read as literal pitches, same as ABC; MusicXML has no
  equivalent of BWW's named ornament tokens. `.mxl` archives are unpacked via
  the system `unzip` tool rather than a bundled ZIP library. Each voice's
  progress (repeats, section boundaries) is tracked independently from its
  own barline markup, so if a source file's voices aren't perfectly
  consistent about where sections start and end, voices can drift apart by a
  second or two over a long tune rather than staying sample-locked — a real
  but minor limitation, not something this app tries to force into sync by
  overriding one voice's timing with another's.

## Credits

- BWW/BMW grammar details (pitch letters, duration codes, dot markers, tie
  tokens, barline/repeat semantics) were cross-checked against
  [tomvodi/limepipes-plugin-bww](https://github.com/tomvodi/limepipes-plugin-bww)
  (MIT licensed), a real working open-source parser for this format.
- The embellishment-to-grace-note-sequence table was transcribed from
  [Ensemble](https://thisisensemble.com)'s own embellishment palettes rather than
  approximated from written tutor descriptions.

## License

MIT — see [LICENSE](LICENSE).
