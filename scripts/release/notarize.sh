#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
artifact=$1
profile=${NOTARY_PROFILE:-$POOKIE_NOTARY_PROFILE}
result=$(mktemp)
trap 'rm -f "$result"' EXIT
options=(--keychain-profile "$profile")
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then options+=(--keychain "$NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$artifact" "${options[@]}" --wait --timeout 30m --output-format json > "$result"
python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted: ' + str(result.get('id')))
print('Apple notarization accepted: ' + result['id'], file=sys.stderr)
PY
