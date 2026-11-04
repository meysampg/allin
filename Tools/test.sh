#!/usr/bin/env bash
# Test levels from docs/PLAN.md section 9.
set -euo pipefail
source "$(dirname "$0")/common.sh"

usage() {
  cat <<U
Usage: Tools/test.sh <level>...   (default: unit)

Levels:
  unit     swift test, skipping Heavy and Sim            (< 2 min)
  heavy    swift test -c release --filter Heavy          (< 10 min)
  sim      swift test -c release --filter Sim            (< 10 min)
  content  swift test --filter ContentTests
  ui       xcodebuild test, AllInAppUITests only
  lint     swift format lint + engine-module import check
  all      unit, content, heavy, sim, lint, ui

A level whose target does not exist yet is skipped with a message, not failed.
U
}

ENGINE_MODULES=(PokerCore PokerEquity PokerHost PokerAI PokerAnalysis Curriculum PokerAbstraction Solver)
FORBIDDEN='^[[:space:]]*(@_exported[[:space:]]+)?(@preconcurrency[[:space:]]+)?import[[:space:]]+(SwiftUI|AppKit|SpriteKit|SwiftData)\b'

swift_test() { # <label> <args...>
  local label="$1"; shift
  if ! have_pkg; then skip "$label: $PKG/Package.swift not found"; return 0; fi
  echo "==> $label"
  swift test --package-path "$PKG" "$@"
}

level_unit() { swift_test unit --skip Heavy --skip Sim; }
level_heavy() { swift_test heavy -c release --filter Heavy; }
level_sim() { swift_test sim -c release --filter Sim; }
level_content() {
  if pkg_has_target 'ContentTests'; then
    swift_test content --filter ContentTests
  else
    skip "content: no ContentTests target yet"
  fi
}
level_ui() {
  if ! have_xcodeproj; then skip "ui: AllIn.xcodeproj not found"; return 0; fi
  if [ ! -d AllInAppUITests ]; then skip "ui: AllInAppUITests not found"; return 0; fi
  echo "==> ui"
  xcodebuild test -project AllIn.xcodeproj -scheme AllIn -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" -only-testing:AllInAppUITests -quiet
}

level_lint() {
  echo "==> lint"
  local dirs=() d
  for d in Packages AllIn AllInAppUITests; do [ -d "$d" ] && dirs+=("$d"); done
  if [ ${#dirs[@]} -eq 0 ]; then
    skip "lint: nothing to format-lint (no Packages/ or AllIn/)"
  elif ! find "${dirs[@]}" -name '*.swift' -not -path '*/.build*/*' | grep -q .; then
    skip "lint: no Swift files yet"
  else
    find "${dirs[@]}" -name '*.swift' -not -path '*/.build*/*' -print0 \
      | xargs -0 swift format lint --configuration .swift-format --strict
  fi

  local bad=0 m dir hits
  for m in "${ENGINE_MODULES[@]}"; do
    dir="$PKG/Sources/$m"
    [ -d "$dir" ] || continue
    hits="$(grep -rEn --include='*.swift' "$FORBIDDEN" "$dir" || true)"
    if [ -n "$hits" ]; then
      echo "FAIL: engine module $m imports a UI/persistence framework:"
      echo "$hits"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] || return 1
  echo "lint OK"
}

level_all() {
  level_unit; level_content; level_heavy; level_sim; level_lint; level_ui
}

[ $# -gt 0 ] || set -- unit
for lvl in "$@"; do
  case "$lvl" in
    -h|--help|help) usage; exit 0 ;;
    unit|heavy|sim|content|ui|lint|all) ;;
    *) echo "Unknown level: $lvl" >&2; usage >&2; exit 2 ;;
  esac
done
for lvl in "$@"; do "level_$lvl"; done
