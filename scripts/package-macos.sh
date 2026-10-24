#!/usr/bin/env bash
# Public artifacts fail closed: no unsigned or unnotarized release path.
set -euo pipefail
source "$(dirname "$0")/release/config.sh"
cd "$root"
python3 scripts/release/policy.py source
app=$(scripts/bundle.sh release production)
version=$(python3 scripts/release/policy.py version)
mkdir -p "$POOKIE_ARTIFACTS"
zip="$POOKIE_ARTIFACTS/Pookie-$version-arm64.zip"
dmg="$POOKIE_ARTIFACTS/Pookie-$version-arm64.dmg"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rm -f "$zip" "$dmg"
ditto -c -k --keepParent "$app" "$zip"
scripts/release/notarize.sh "$zip"
xcrun stapler staple "$app" >&2
python3 scripts/release/native.py verify "$app" >&2
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"
mkdir "$work/image"
ditto "$app" "$work/image/Pookie.app"
ln -s /Applications "$work/image/Applications"
hdiutil create -volname Pookie -srcfolder "$work/image" -ov -format UDZO "$dmg" >&2
codesign --force --timestamp --sign "$POOKIE_SIGN_IDENTITY" "$dmg" >&2
scripts/release/notarize.sh "$dmg"
xcrun stapler staple "$dmg" >&2
xcrun stapler validate "$dmg" >&2
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" >&2
# Inspect the bytes Sparkle receives, rather than only the original app.
ditto -x -k "$zip" "$work/extracted"
python3 scripts/release/native.py verify "$work/extracted/Pookie.app" >&2
# Tagged source contains the manifest, lockfile, build scripts and build instructions.
git archive --format=tar.gz --prefix="Pookie-$version/" "v$version" \
  > "$POOKIE_ARTIFACTS/Pookie-$version-source.tar.gz"
printf '%s\n' "$zip" "$dmg" "$POOKIE_ARTIFACTS/Pookie-$version-source.tar.gz"
