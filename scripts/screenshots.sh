#!/bin/bash
# Regenerates the README screenshots in assets/ from a fresh build, using the sample script.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null 2>&1
SAMPLE="$(sed -n '/sampleScript = """/,/^    """/p' Sources/Model.swift | sed '1d;$d' | sed 's/^    //')"
for variant in dark light; do
  RAW=$(mktemp -d)
  open -W -n build/Notchling.app --args --show --snapshot "$RAW" -script "$SAMPLE" -mode steady -appearance "$variant"
  swift scripts/frame_screenshots.swift "$RAW" assets "$variant"
  rm -rf "$RAW"
done
echo "Wrote assets/hero.png, assets/editor-light.png and assets/editor-dark.png"
