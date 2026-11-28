# PipePlayer

A free Mac app that plays bagpipe tune files out loud. No pipes or practice
chanter needed.

It opens tunes from **Bagpipe Music Writer**, **Bagpipe Musicworks Gold**,
**Bagpipe Reader**, **Ensemble**, or anything that exports **MusicXML**, and
plays them with the grace notes, doublings, throws, and other Highland
ornamentation intact.

## Why

Tune collections pile up as `.bww`, `.bmw`, `.abc`, and `.musicxml` files,
and they stay silent until you sit down with an instrument and work them
out. PipePlayer plays them so you can hear a tune before learning it, check
a transcription for mistakes, or send someone a recording.

## What it does

- Opens `.abc`, `.bww`, `.bmw`, `.musicxml`, `.xml`, and `.mxl` files
- Plays ornaments from a reference table of what pipers actually play:
  doublings, throws, grips, taorluath, birls, strikes, crunluath
- One tab per tune. Starting playback in one tab stops the others
- Play, pause, seek, tempo, volume, and an optional drone
- Loop the whole tune or a single part, for drilling it or playing along
- MusicXML harmony arrangements play all parts together, with a mute
  checkbox per part
- Exports to WAV, AAC, or MP4 using your current instrument and settings
- Uses Apple's built-in instrument bank, a SoundFont you supply, or any
  virtual instrument installed on your Mac
- Can act as a MIDI source for a DAW, notation app, or hardware synth,
  in sync with playback

## Getting it

Download the latest build from the
[Releases page](https://github.com/brokosz/PipePlayer/releases/latest) and
drag `PipePlayer.app` into Applications.

It's not from the App Store, so the first launch gets an "unidentified
developer" warning. Control-click the app and choose **Open**. You only have
to do this once.

## Using it

Open a tune (**File → Open…** or drag it onto the window) and press play.

- The bar across the top shows each part of the tune and where you are.
  Click a part to jump to it
- The loop button (⟳) cycles through looping the tune, looping just the
  part you're in, and off. While a part loops, click another part to loop
  that one instead. You can change the tempo without stopping
- Tempo, volume, and the other controls change playback only. The file is
  never modified
- Strathspeys are played pointed, the way a piper plays them, instead of
  the softer swing of the written rhythm
- Each tune opens in its own tab. Opening a tune that's already open
  switches to its tab
- **File → New Set** makes a set list: tunes that play straight through,
  each once, the next coming in on the beat, for an MSR or a few jigs
  together. Add tunes with + or by dropping them, drag to reorder, and set
  each tune's tempo while it plays. Save it as a `.pipeset` next to your
  tunes; changes save as you go
- To play seconds or another harmony along with a tune, drop its file on
  the right half of the window (**Add as Harmony**), or use **File → Add
  Harmony…**. It follows the tune's tempo and repeats, and gets its own mute
  checkbox. Right-click that checkbox to remove it
- Tabs come back after you quit, with the same tempo, muted voices and
  added harmonies
- The export button (⬆) saves what you're hearing as an audio file

## Privacy

PipePlayer collects nothing and has no network access. No account, no
analytics. It remembers your recent files and open tabs between launches,
stored locally on your Mac.

## For developers

Build instructions, internals, and file-format notes are in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT. See [LICENSE](LICENSE).
