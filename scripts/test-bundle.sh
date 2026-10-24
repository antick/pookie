#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Missing signing authority must fail before a production build or any packaging work.
if env -u POOKIE_SIGN_IDENTITY "$root/scripts/bundle.sh" release production > "$work/result" 2>&1; then
  echo 'FAIL: production accepted missing signing identity' >&2; exit 1
fi
grep -q 'Developer ID' "$work/result"
app=$("$root/scripts/bundle.sh" debug development)
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.pookie.pet.dev'
assert info['PookieChannel'] == 'development'
assert info['CFBundleIconFile'] == 'AppIcon'
assert 'SUFeedURL' not in info and 'SUPublicEDKey' not in info
for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md', 'Sparkle-LICENSE.txt', 'AppIcon.icns'):
    assert (app / 'Contents/Resources' / name).stat().st_size > 0, name
assert (app / 'Contents/Frameworks/Sparkle.framework/Versions/Current').is_symlink()
PY
codesign --verify --deep --strict "$app"
python3 "$root/scripts/release/native.py" architectures "$app"
"$app/Contents/MacOS/Pookie" --selftest
echo 'Verified development bundle identity, icon, notices, framework, signature and selftests.'
