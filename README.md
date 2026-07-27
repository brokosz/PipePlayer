# PipePlayer

A simple macOS app for playing back Great Highland Bagpipe tune files —
`.abc`, `.bww`, and `.bmw` — with standard transport controls and a choice of
sound sources.

## Features

- Parses ABC notation and the BWW/BMW "tune code" text format shared by
  Bagpipe Music Writer, Bagpipe Musicworks Gold, and Bagpipe Reader
- Full grace-note/embellishment expansion (doublings, throws, grips,
  taorluath, birl, strikes, crunluath, and the wider piobaireachd vocabulary)
  using ground-truth grace-note sequences, not approximated ones
- Transport controls: play/pause/stop, seek, tempo (numeric field + stepper),
  volume, loop
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
- Tempo is read as a flat quarter-note BPM value regardless of time
  signature (including cut time / 2÷2) — this was cross-checked against a
  real reference parser rather than assumed.

## Credits

- BWW/BMW grammar details (pitch letters, duration codes, dot markers, tie
  tokens, barline/repeat semantics) were cross-checked against
  [tomvodi/limepipes-plugin-bww](https://github.com/tomvodi/limepipes-plugin-bww)
  (MIT licensed), a real working open-source parser for this format.
- The embellishment-to-grace-note-sequence table was transcribed from
  [Ensemble](https://thisisensemble.com)'s own `editor.js` — its internal,
  ground-truth vocabulary for the same ornament tokens — rather than
  approximated from written tutor descriptions.

## License

MIT — see [LICENSE](LICENSE).
