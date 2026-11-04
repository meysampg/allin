#!/usr/bin/env bash
# Builds the Swift package and, when AllIn.xcodeproj exists, the macOS app into build/DerivedData.
set -euo pipefail
source "$(dirname "$0")/common.sh"

usage() {
  cat <<U
Usage: Tools/build.sh [-h|--help]

Builds Packages/AllInKit (swift build) and, if AllIn.xcodeproj exists, the
AllIn scheme (Debug) with xcodebuild into build/DerivedData (gitignored).
Missing pieces are skipped with a message. Env: CONFIGURATION=Debug|Release.
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; "") ;; *) usage >&2; exit 2 ;; esac

CONFIGURATION="${CONFIGURATION:-Debug}"

if have_pkg; then
  echo "==> swift build ($PKG)"
  swift build --package-path "$PKG"
  if [ -d Themes ]; then
    echo "==> theme validate"
    "$(swift build --package-path "$PKG" --show-bin-path)/allin-tool" theme validate Themes
  fi
else
  skip "$PKG/Package.swift not found; package not built"
fi

if have_xcodeproj; then
  echo "==> xcodebuild AllIn ($CONFIGURATION)"
  xcodebuild -project AllIn.xcodeproj -scheme AllIn -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" -quiet build
else
  skip "AllIn.xcodeproj not found; app not built"
fi
echo "Build done."
