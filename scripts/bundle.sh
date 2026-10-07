#!/usr/bin/env bash
#
# Assemble a double-clickable Pookie.app from the SwiftPM build product.
#
# A plain `swift run` works fine for development, but a bundle is what gives
# macOS the Info.plist it needs (LSUIElement, bundle identifier) for stable
# hotkeys, Screen Recording / Accessibility prompts, and `open`.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ROOT="$PWD"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/modulecache"
mkdir -p "$ROOT/.build/modulecache"

# --disable-sandbox: SwiftPM wraps manifest compilation in sandbox-exec, which
# is unavailable in some restricted shells. Safe here — no untrusted packages.
swift build -c "$CONFIG" --disable-sandbox
BIN_PATH="$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path)"

APP="$ROOT/build/Pookie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Pookie" "$APP/Contents/MacOS/Pookie"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. Without one, macOS re-prompts for permissions on every
# rebuild because the binary's identity changes.
if command -v codesign >/dev/null 2>&1; then
    if codesign --force --sign - "$APP" >/dev/null 2>&1; then
        echo "ad-hoc signed"
    else
        echo "note: ad-hoc codesign failed; the app still runs"
    fi
fi

echo "built $APP"
echo "run it with:  open '$APP'"
