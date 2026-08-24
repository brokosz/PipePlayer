# PipePlayer

A free Mac app that plays your bagpipe tune files out loud — no pipes, no
practice chanter, no other app required.

If you've got tunes saved from **Bagpipe Music Writer**, **Bagpipe
Musicworks Gold**, **Bagpipe Reader**, **Ensemble**, or any notation program
that can export **MusicXML**, PipePlayer opens them and plays them back with
real grace notes, doublings, throws, and the rest of Highland piping's
ornamentation — not a flattened, robotic version of the tune.

## Why

Tune collections pile up as files — `.bww`, `.bmw`, `.abc`, `.musicxml` — and
most of them are silent until you sit down with pipes or a chanter and work
them out. PipePlayer just plays them, so you can hear a tune before you
learn it, check a transcription for mistakes, or send someone a recording
without picking up an instrument.

## What it does

- **Opens ABC, BWW/BMW, and MusicXML tune files** (`.abc`, `.bww`, `.bmw`,
  `.musicxml`, `.xml`, `.mxl`) — the common formats Highland piping software
  actually saves in
- **Plays the ornamentation properly.** Doublings, throws, grips,
  taorluath, birl, strikes, crunluath — the grace notes that make a tune
  sound like piping and not a music box — are expanded from a real
  reference table, not guessed at
- **Multiple tunes open at once**, each in its own tab, each independent —
  switch between them freely, and starting one stops whichever other tab
  was playing, so you're never listening to two at once by accident
- **A real transport**: play, pause, seek, adjustable tempo and volume,
  looping, and an optional continuous drone underneath the melody
- **Harmony arrangements** (a MusicXML file with a melody and one or more
  harmony parts) play together, with a mute checkbox per part so you can
  solo or drop any of them
- **Export to an audio file** (WAV, AAC, or MP4) using whatever instrument
  and settings you've got dialed in — share a tune as a real audio file, no
  screen recording required
- **Choose the sound**: Apple's built-in instrument bank, any SoundFont file
  you supply, or any other virtual instrument installed on your Mac
- **Send MIDI to another app** — PipePlayer can act as a MIDI source for a
  DAW, notation program, or hardware synth, playing along in exact sync

## Getting it

Download the latest build from the
[Releases page](https://github.com/brokosz/PipePlayer/releases/latest) and
drag `PipePlayer.app` into your Applications folder.

Since this isn't distributed through the Mac App Store, the first time you
open it macOS will warn you it's from an unidentified developer. Right-click
(or Control-click) the app and choose **Open** — you'll only need to do this
once.

## Using it

Open a tune file (**File → Open…**, or just drag it onto the window) and
press play. From there:

- The bar across the top shows each part of the tune and highlights where
  you are — click any part to jump straight to it
- Drag the tempo, volume, and other controls to taste; none of it affects
  the file itself, just how it plays back
- Open another tune in a new tab (**File → New Window**) to compare two
  arrangements, or queue up a set
- When it sounds the way you want, use the export button (⬆) to save it as
  an audio file

## Privacy

PipePlayer doesn't collect or send anything anywhere. It reads the file you
open and plays it through your Mac's speakers — that's it. No account, no
analytics, no network access. The only thing it remembers between launches
is your recent-files list, kept entirely on your own machine.

## For developers

Building from source, the parser/playback internals, and notes on how
specific file-format quirks are handled all live in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT — see [LICENSE](LICENSE).
