#!/usr/bin/env bash
# Disposable file-based keys only: never reads or writes a real Keychain item.
set -euo pipefail
source "$(dirname "$0")/config.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077
openssl rand -base64 32 > "$work/key"
printf 'original update archive\n' > "$work/update.zip"
public=$(swift -e 'import Foundation; import CryptoKit
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))!)
print(key.publicKey.rawRepresentation.base64EncodedString())' "$work/key")
signature=$("$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" -p "$work/update.zip")
"$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" --verify "$work/update.zip" "$signature"
if ! swift "$root/scripts/release/verify-update.swift" "$work/update.zip" "$signature" "$public"; then
  echo 'FAIL: valid update rejected by public-key verifier' >&2
  exit 1
fi
printf 'modified archive\n' >> "$work/update.zip"
if "$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" --verify \
  "$work/update.zip" "$signature" > "$work/result" 2>&1; then
  echo 'FAIL: upstream verifier accepted tampered archive' >&2; exit 1
fi
if swift "$root/scripts/release/verify-update.swift" "$work/update.zip" "$signature" "$public" > "$work/result" 2>&1; then
  echo 'FAIL: public-key verifier accepted tampered archive' >&2; exit 1
fi
printf '<rss><channel><title>signature test</title></channel></rss>\n' > "$work/appcast.xml"
"$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" "$work/appcast.xml"
"$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" --verify "$work/appcast.xml"
sed -i '' 's/signature test/tampered title/' "$work/appcast.xml"
if "$POOKIE_SPARKLE_BIN/sign_update" --ed-key-file "$work/key" --verify "$work/appcast.xml" > "$work/result" 2>&1; then
  echo 'FAIL: upstream verifier accepted tampered feed' >&2; exit 1
fi
echo 'Verified: valid update/feed accepted; tampered archive/feed rejected.'
