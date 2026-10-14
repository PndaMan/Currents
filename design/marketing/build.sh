#!/usr/bin/env bash
# Render the Currents poster to out/. Screenshots in shots/ come from the
# "App Store Screenshots" workflow (screenshot mode seeds the demo data).
set -euo pipefail
cd "$(dirname "$0")"
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"
mkdir -p out
node render.cjs poster.html out/currents-poster.png 2000 1930
