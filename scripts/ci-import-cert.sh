#!/bin/bash
# CI only: imports the code-signing certificate into a temporary keychain and prints its SHA-1, which
# make-app.sh takes as CODESIGN_IDENTITY.  Input: CODESIGN_P12 (base64 .p12) and CODESIGN_P12_PASSWORD.
set -euo pipefail
: "${CODESIGN_P12:?}" "${CODESIGN_P12_PASSWORD:?}"
DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KC="$DIR/cove-signing.keychain-db"
KP=$(uuidgen)

printf '%s' "$CODESIGN_P12" | base64 --decode > "$DIR/cove.p12"
security create-keychain -p "$KP" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KP" "$KC"
security import "$DIR/cove.p12" -k "$KC" -P "$CODESIGN_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
rm -f "$DIR/cove.p12"
# Let codesign use the key without a dialog
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KP" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')

# Self-signed, so it is listed as not trusted; codesign can still sign with it (trust isn't needed to sign)
ID=$(security find-identity -p codesigning "$KC" | awk '/^ *[0-9]+\)/ {print $2; exit}')
[ -n "$ID" ] || { echo "No code-signing identity found in CODESIGN_P12" >&2; exit 1; }
echo "$ID"
