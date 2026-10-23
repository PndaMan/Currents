#!/usr/bin/env bash
# Downloads the app-store-screenshots branch (published by
# .github/workflows/screenshots.yml) and lays it out for fastlane deliver.
#
#   ios/build/appstore-screenshots/branch/   the branch as published: raw/, framed/, watch.png, events/
#   ios/build/appstore-screenshots/deliver/  one folder per localisation: the framed set plus watch.png
#
# deliver reads every PNG in a locale folder and picks the display type from
# the pixel size: 1320x2868 is APP_IPHONE_67 (the 6.9-inch slot) and 410x502 is
# APP_WATCH_ULTRA. Prints the deliver folder on the last line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/ios/build/appstore-screenshots}"
BRANCH="${SCREENSHOTS_BRANCH:-app-store-screenshots}"
LOCALES=(en-US en-GB es-MX)

git -C "$ROOT" fetch --quiet origin "$BRANCH"
COMMIT="$(git -C "$ROOT" rev-parse FETCH_HEAD)"

rm -rf "$OUT/branch" "$OUT/deliver"
mkdir -p "$OUT/branch" "$OUT/deliver"
git -C "$ROOT" archive "$COMMIT" | tar -x -C "$OUT/branch"

shopt -s nullglob
framed=("$OUT/branch/framed/"*.png)
if [ "${#framed[@]}" -eq 0 ]; then
  echo "No framed screenshots on $BRANCH ($COMMIT). Run the screenshots workflow first." >&2
  exit 1
fi

for locale in "${LOCALES[@]}"; do
  mkdir -p "$OUT/deliver/$locale"
  cp "${framed[@]}" "$OUT/deliver/$locale/"
  if [ -f "$OUT/branch/watch.png" ]; then
    cp "$OUT/branch/watch.png" "$OUT/deliver/$locale/watch.png"
  fi
done

echo "$BRANCH at ${COMMIT:0:8}: ${#framed[@]} framed, watch $([ -f "$OUT/branch/watch.png" ] && echo yes || echo no), events $([ -d "$OUT/branch/events" ] && ls "$OUT/branch/events" | tr '\n' ' ' || echo none)" >&2
echo "$OUT/deliver"
