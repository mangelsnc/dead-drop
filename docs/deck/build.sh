#!/usr/bin/env bash
# Build the slide deck into a 1920x1080 PDF.
#
# The slides are plain HTML, one <section> per slide, ordered by deck.json.
# Chrome is the renderer because it honours @page size — the PDF tools that
# take a paper format (A4, Letter) cannot produce a 16:9 page.
#
#   ./docs/deck/build.sh [output.pdf]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-$here/deaddrop-deck.pdf}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 - "$here" "$work" <<'PY'
import json, sys
from pathlib import Path
here, work = Path(sys.argv[1]), Path(sys.argv[2])
order = json.loads((here / 'deck.json').read_text())['order']
slides = [(here / 'slides' / f'{n}.html').read_text() for n in order]
(work / 'deck.html').write_text("""<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>DeadDrop — Transferencia air-gapped por QR</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@300;400;600;700&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
<style>
 @page { size: 1920px 1080px; margin: 0; }
 html,body{margin:0;padding:0;background:#fff}
 section{width:1920px;height:1080px;box-sizing:border-box;position:relative;
         overflow:hidden;page-break-after:always;break-after:page}
 section:last-of-type{page-break-after:auto;break-after:auto}
 aside{display:none}
</style></head><body>
""" + "\n".join(slides) + "\n</body></html>")
print(f'{len(slides)} slides')
PY

# Served over HTTP, not file://, so the webfonts load.
python3 -m http.server 8799 --directory "$work" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -rf "$work"' EXIT
sleep 1

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$chrome" ] || chrome="$(command -v google-chrome || command -v chromium || true)"
if [ -z "$chrome" ]; then
  echo "Chrome/Chromium not found — needed to render the PDF." >&2
  exit 1
fi

"$chrome" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$out" --virtual-time-budget=15000 \
  "http://localhost:8799/deck.html" 2>/dev/null

echo "✔ $out"
