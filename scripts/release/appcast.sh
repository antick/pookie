#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
cd "$root"
python3 scripts/release/policy.py info
version=$(python3 scripts/release/policy.py version)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive="Pookie-$version-arm64.zip"
cp "$POOKIE_ARTIFACTS/$archive" "$work/"
python3 scripts/release/policy.py notes > "$work/Pookie-$version-arm64.txt"
key=(--account "$POOKIE_SPARKLE_ACCOUNT")
if [ -n "${SPARKLE_KEY_FILE:-}" ]; then key=(--ed-key-file "$SPARKLE_KEY_FILE"); fi
"$POOKIE_SPARKLE_BIN/generate_appcast" "${key[@]}" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/$POOKIE_REPOSITORY/releases/download/v$version/" \
  --link "https://github.com/$POOKIE_REPOSITORY/releases/tag/v$version" "$work" >&2
# Require a signed feed even if upstream generation changes its defaults.
"$POOKIE_SPARKLE_BIN/sign_update" "${key[@]}" "$work/appcast.xml" >&2
"$POOKIE_SPARKLE_BIN/sign_update" "${key[@]}" --verify "$work/appcast.xml" >&2
cp "$work/appcast.xml" "$POOKIE_ARTIFACTS/appcast.xml"
python3 scripts/release/policy.py feed
signature=$(python3 - "$POOKIE_ARTIFACTS/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get(
    '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)
public=$( /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$POOKIE_PLIST" )
"$POOKIE_SPARKLE_BIN/sign_update" "${key[@]}" --verify "$POOKIE_ARTIFACTS/$archive" "$signature" >&2
swift scripts/release/verify-update.swift "$POOKIE_ARTIFACTS/$archive" "$signature" "$public"
python3 scripts/release/policy.py checksums
python3 scripts/release/policy.py assets
mkdir -p "$POOKIE_ARTIFACTS/site"
cp "$POOKIE_ARTIFACTS/appcast.xml" "$POOKIE_ARTIFACTS/site/appcast.xml"
