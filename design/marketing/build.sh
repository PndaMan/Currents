#!/usr/bin/env bash
# Render the hero poster and the App Store frames into out/.
#   ./build.sh            (expects real screenshots in shots/)
set -euo pipefail
cd "$(dirname "$0")"
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"
mkdir -p out
[ -f chart-hero.svg ] || python3 make_chart.py 2400 3200 chart-hero.svg 7
[ -f chart-wide.svg ] || python3 make_chart.py 9240 2868 chart-wide.svg 11
node render.cjs hero.html out/hero.png 2400 3200
node render.cjs appstore.html out/appstore-strip.png 9240 2868
python3 - <<'PY'
from PIL import Image
strip = Image.open('out/appstore-strip.png').convert('RGB')
for i in range(strip.width // 1320):
    strip.crop((i * 1320, 0, (i + 1) * 1320, 2868)).save(f'out/appstore-{i + 1:02d}.png')
Image.open('out/hero.png').convert('RGB').save('out/hero.jpg', quality=90)
print('sliced', strip.width // 1320, 'frames')
PY
