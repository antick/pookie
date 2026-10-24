#!/usr/bin/env bash
# Keep the feed private until all exact, verified assets are publicly downloadable.
set -euo pipefail
source "$(dirname "$0")/config.sh"
cd "$root"
python3 scripts/release/policy.py source
python3 scripts/release/policy.py assets
version=$(python3 scripts/release/policy.py version)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 scripts/release/policy.py notes > "$work/notes.md"
names=()
while IFS= read -r name; do names+=("$name"); done < <(python3 scripts/release/policy.py names)
assets=()
for name in "${names[@]}"; do assets+=("$POOKIE_ARTIFACTS/$name"); done
gh release create "v$version" --repo "$POOKIE_REPOSITORY" --verify-tag --draft \
  --title "Pookie $version" --notes-file "$work/notes.md" "${assets[@]}"
mkdir "$work/draft"
gh release download "v$version" --repo "$POOKIE_REPOSITORY" --dir "$work/draft"
for name in "${names[@]}"; do cmp "$POOKIE_ARTIFACTS/$name" "$work/draft/$name"; done
gh release edit "v$version" --repo "$POOKIE_REPOSITORY" --draft=false --latest
# No authentication: prove the public URLs work before the Pages job is allowed to start.
mkdir "$work/public"
for name in "${names[@]}"; do
  curl --fail --silent --show-error --location --retry 5 --retry-delay 2 \
    "https://github.com/$POOKIE_REPOSITORY/releases/download/v$version/$name" \
    --output "$work/public/$name"
  cmp "$POOKIE_ARTIFACTS/$name" "$work/public/$name"
done
(cd "$work/public" && shasum -a 256 --check SHA256SUMS)
echo "Verified all five public release assets for v$version."
