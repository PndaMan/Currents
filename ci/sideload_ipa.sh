#!/usr/bin/env bash
# Package a built Currents.app as the sideload IPA (Payload/Currents.app,
# fakesigned with ldid). Used by both the sideload and TestFlight jobs in
# .github/workflows/ios.yml so the two IPAs come out the same.
#
# Usage: sideload_ipa.sh <path/to/Currents.app> <entitlements.plist> <out.ipa>
set -euo pipefail

APP_PATH=$1
ENTITLEMENTS=$2
OUT_IPA="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"

if [ ! -d "$APP_PATH" ]; then
  echo "App not found at $APP_PATH"
  exit 1
fi
echo "App size: $(du -sh "$APP_PATH" | cut -f1)"

command -v ldid >/dev/null || brew install ldid

WORK=$(mktemp -d)
mkdir "$WORK/Payload"
cp -R "$APP_PATH" "$WORK/Payload/"
APP_COPY="$WORK/Payload/Currents.app"

# CloudCapability (CommunityService.swift) reads this and keeps CloudKit off:
# a sideloaded install is re-signed without the iCloud entitlement.
plutil -replace CurrentsSideload -bool YES "$APP_COPY/Info.plist"

# An archived app carries the App Store profiles; the sideloader adds its own.
find "$APP_COPY" -name embedded.mobileprovision -delete

# Fakesign with ldid for sideloading (TrollStore/Sideloader compatible). This
# comes after the Info.plist edit because the signature covers Info.plist.
ldid -S"$ENTITLEMENTS" "$APP_COPY/Currents"

rm -f "$OUT_IPA"
(cd "$WORK" && zip -qr "$OUT_IPA" Payload)
rm -rf "$WORK"
echo "Wrote $OUT_IPA ($(du -sh "$OUT_IPA" | cut -f1))"
