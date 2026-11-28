# PipePlayer website

## Intent

A public site where pipers who have never heard of PipePlayer can find it,
understand what it does, hear it, and download it. Not just for our band.

## Goals

- Make the case in the first screen: what it is, a way to hear it, a download.
- Let people hear the app before installing it.
- Always link to the latest release without editing the site.

Non-goals: docs, a blog, a changelog (the Releases page covers that).
Anti-goals: a generic theme look; a build toolchain in a Swift repo.

## Approaches

1. **Hand-written HTML/CSS in `site/`, published by a GitHub Actions
   workflow** — chosen. Full control of the look, no dependencies; a
   second page would mean copying header/footer by hand.
2. Jekyll — shared layouts, but stock themes look generic and a custom
   look means overriding most of one.
3. Astro or similar — a Node toolchain for one page.

## Look (decided with mockups)

- Colors from the app icon: deep green `#134d42` → `#0b3530`, gold
  `#f4b21f`, navy `#262f45` (the play button), tartan green `#1f6b3e`.
- Type: Outfit (Google Fonts), extra light 200 for headings, 300 body,
  500 for buttons.
- Hero ("C"): "Your tunes, *out loud.*" with the gold words, a short line
  on formats, gold pill Download button, "Free · macOS 13+". On the right,
  the icon's navy-and-gold play button, large, with gold rings pulsing
  out. Clicking it plays a sample tune; while playing, it shows pause and
  the rings keep going.

## Page, top to bottom

1. Hero (above).
2. Screenshot of the app with a tune open.
3. Hear it: 2–3 short clips, each a title, the tune type, and a play
   button in the same style. One plays at a time.
4. Opens your files: the formats (.bww, .bmw, .abc, .musicxml/.xml/.mxl)
   and the programs they come from.
5. Features: ornaments, part looping, sets, harmonies, export, MIDI out,
   instruments (built-in, SoundFont, AU).
6. Install: download, drag to Applications, the first-launch
   "unidentified developer" step (copy from the README).
7. Footer: GitHub, license, free.

## Constraints

- Download links point at `releases/latest`, never a version.
- Works at phone width; respects `prefers-reduced-motion` (rings stop).
- Audio as AAC/M4A, a minute or less each, to keep the page light.
- Pages served from `brokosz.github.io/PipePlayer`; the workflow deploys
  `site/` only, so `docs/` stays out of the site.

## Left to the builder

- Copy wording, section styling below the hero, feature icons.
- Screenshots: taken from the installed app with `screencapture`.
- Audio: exported from the app. Which tunes is Brad's call — traditional
  or his own, since the clips are published.
