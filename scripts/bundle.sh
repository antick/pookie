#!/usr/bin/env bash
# Optimization and app identity are separate: even release builds default to Dev.
set -euo pipefail
source "$(dirname "$0")/release/config.sh"
config=${1:-debug}
channel=${2:-development}
case "$config" in debug|release) ;; *) release_fail 'Expected debug or release' ;; esac
case "$channel" in development|production) ;; *) release_fail 'Expected development or production' ;; esac
[ "$(uname -m)" = "$POOKIE_ARCH" ] || release_fail 'Packaging requires an Apple silicon Mac.'
identity=-
if [ "$channel" = production ]; then
  : "${POOKIE_SIGN_IDENTITY:?Production requires a Developer ID Application signing identity}"
  [ "$POOKIE_SIGN_IDENTITY" != - ] || release_fail 'Production requires Developer ID signing.'
  identity=$POOKIE_SIGN_IDENTITY
  python3 "$root/scripts/release/policy.py" info
  app="$root/build/release/Pookie.app"
else
  app="$root/build/Pookie Dev.app"
fi
cd "$root"
export CLANG_MODULE_CACHE_PATH="$root/.build/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/modulecache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build -c "$config" --arch "$POOKIE_ARCH" --disable-sandbox >&2
bin=$(swift build -c "$config" --arch "$POOKIE_ARCH" --disable-sandbox --show-bin-path)
[ -d "$POOKIE_SPARKLE_FRAMEWORK" ] || release_fail 'Resolved Sparkle framework is missing.'
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/Pookie" "$app/Contents/MacOS/Pookie"
python3 scripts/release/bundle_info.py "$app/Contents/Info.plist" "$channel"
for name in LICENSE THIRD_PARTY_NOTICES.md; do
  cp "$root/$name" "$app/Contents/Resources/$name"
done
cp "$root/.build/checkouts/Sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
# ditto keeps Sparkle's versioned framework symlinks intact.
ditto "$POOKIE_SPARKLE_FRAMEWORK" "$app/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$app/Contents/MacOS/Pookie" | grep -F '@executable_path/../Frameworks' >/dev/null; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Pookie"
fi
scripts/generate-icons.sh "$bin/Pookie" "$channel" "$app/Contents/Resources/AppIcon.icns"
python3 scripts/release/native.py sign "$app" "$identity" "$channel"
printf '%s\n' "$app"
