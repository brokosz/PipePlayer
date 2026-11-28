#!/bin/bash
# Sanity checks for the site, run locally and before every Pages deploy.
set -euo pipefail
cd "$(dirname "$0")"

fail() { echo "FAIL: $*"; exit 1; }

for f in index.html style.css main.js; do
  [ -f "$f" ] || fail "missing $f"
done

# Every relative src/href/data-audio in the page points at a real file.
grep -oE '(src|href|data-audio)="[^"#]+"' index.html | sed -E 's/^[^"]*"//; s/"$//' | while read -r ref; do
  case "$ref" in
    http*|mailto:*|//*) continue ;;
  esac
  [ -e "$ref" ] || fail "index.html references missing file: $ref"
done

# Downloads always go to the latest release.
releases=$(grep -oE 'https://github\.com/brokosz/PipePlayer/releases[^"]*' index.html || true)
[ "$(echo "$releases" | grep -c . || true)" -ge 2 ] || fail "expected at least two release links"
echo "$releases" | grep -vqx 'https://github.com/brokosz/PipePlayer/releases/latest' \
  && fail "release link not pointing at /releases/latest: $(echo "$releases" | grep -vx 'https://github.com/brokosz/PipePlayer/releases/latest' | head -1)"

grep -q 'prefers-reduced-motion' style.css || fail "style.css doesn't handle prefers-reduced-motion"
grep -q 'Outfit' style.css || fail "style.css doesn't use Outfit"
grep -q 'macOS 13+' index.html || fail "index.html doesn't say macOS 13+"
for ext in .bww .bmw .abc .musicxml .mxl; do
  grep -qF "$ext" index.html || fail "index.html doesn't mention $ext"
done

[ "$(grep -c 'data-audio=' index.html)" -ge 4 ] || fail "expected the hero button plus three clips"

echo "site checks passed"
