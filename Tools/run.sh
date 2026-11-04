#!/usr/bin/env bash
# Builds and launches the macOS app. Extra arguments are passed to the app (DebugLaunch args).
set -euo pipefail
source "$(dirname "$0")/common.sh"

usage() {
  cat <<U
Usage: Tools/run.sh [-h|--help] [app arguments...]

Builds the app (Tools/build.sh) and launches it from build/DerivedData.
Arguments are passed through, for example:
  Tools/run.sh -AllInDemo YES -AllInScreen table -AllInSeed 7
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if ! have_xcodeproj; then
  skip "AllIn.xcodeproj not found; nothing to run yet"
  exit 0
fi
"$ROOT/Tools/build.sh"
APP="$DERIVED/Build/Products/Debug/AllIn.app"
[ -d "$APP" ] || { echo "App bundle not found at $APP" >&2; exit 1; }
echo "==> launching $APP"
exec "$APP/Contents/MacOS/AllIn" "$@"
