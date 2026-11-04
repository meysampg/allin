# Shared helpers, sourced by the other Tools scripts. Not meant to be run directly.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PKG="Packages/AllInKit"
DERIVED="$ROOT/build/DerivedData"
cd "$ROOT"

have_pkg() { [ -f "$ROOT/$PKG/Package.swift" ]; }
have_xcodeproj() { [ -d "$ROOT/AllIn.xcodeproj" ]; }
skip() { echo "SKIP: $*"; }
# True when the package declares a test target whose name matches $1 (regex).
pkg_has_target() { have_pkg && grep -Eq "$1" "$ROOT/$PKG/Package.swift"; }
