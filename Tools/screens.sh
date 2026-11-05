#!/usr/bin/env bash
# Captures a PNG of the app window for each demo screen into build/screens/.
set -euo pipefail
source "$(dirname "$0")/common.sh"

usage() {
  cat <<U
Usage: Tools/screens.sh [-h|--help] [screen-id...]

Launches the app in demo mode (-AllInDemo YES -AllInScreen <id> -AllInSeed 7) for each
screen id and saves build/screens/NN-<id>.png using screencapture. With no ids, uses
SCREENS from the environment, else all known screens. Prints "no screens yet" until
the app has demo screens. Needs Screen Recording permission for the terminal.
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if ! have_xcodeproj || [ ! -f AllIn/App/DebugLaunch.swift ]; then
  echo "no screens yet (AllIn.xcodeproj or AllIn/App/DebugLaunch.swift missing)"
  exit 0
fi

DEFAULT="menu career venue lesson lesson:3 lobby table review boss result tournament gym rivals mygame settings arena"
SCREENS=("$@")
[ ${#SCREENS[@]} -gt 0 ] || read -r -a SCREENS <<<"${SCREENS_ENV:-${SCREENS:-$DEFAULT}}"

"$ROOT/Tools/build.sh"
APP="$DERIVED/Build/Products/Debug/AllIn.app/Contents/MacOS/AllIn"
OUT="$ROOT/build/screens"
mkdir -p "$OUT"
i=1
for s in "${SCREENS[@]}"; do
  "$APP" -AllInDemo YES -AllInScreen "$s" -AllInSeed 7 &
  pid=$!
  sleep 3
  wid="$(osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$pid"') to get id of window 1' 2>/dev/null || true)"
  file="$(printf '%s/%02d-%s.png' "$OUT" "$i" "${s//:/-}")"
  echo "==> $s -> $file"
  if [ -n "$wid" ]; then screencapture -x -o -l "$wid" "$file"; else screencapture -x "$file"; fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  i=$((i + 1))
done
echo "Screens in $OUT"
