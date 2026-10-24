#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
app=$("$root/scripts/bundle.sh" "${CONFIG:-debug}" development)
exec "$app/Contents/MacOS/Pookie" "$@"
