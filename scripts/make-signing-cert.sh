#!/bin/bash
# One-time setup: creates Cove's self-signed code-signing certificate (valid 10 years).
#
#   scripts/make-signing-cert.sh            # writes cove-signing.p12 and prints what to do next
#   scripts/make-signing-cert.sh --github   # also stores it as GitHub Actions secrets with `gh`
#
# Why: ad-hoc signatures change with every build, so macOS treats each update as a different app (Keychain
# prompts after every update). With one stable certificate, every release is recognized as the same app.
# It is not an Apple Developer ID: Gatekeeper still shows the "unidentified developer" warning on first launch.
set -euo pipefail
OSSL=/usr/bin/openssl          # macOS LibreSSL: writes .p12 files that `security import` reads on every macOS
OUT=cove-signing.p12
PASS=$(uuidgen)
[ -e "$OUT" ] && { echo "$OUT already exists; not overwriting it." >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Cove Code Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

"$OSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
LEGACY=""; "$OSSL" version | grep -q '^OpenSSL 3' && LEGACY="-legacy"
"$OSSL" pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "Cove Code Signing" \
  -out "$OUT" -passout "pass:$PASS"
chmod 600 "$OUT"

if [ "${1:-}" = "--github" ]; then
  base64 -i "$OUT" | gh secret set CODESIGN_P12 -R J0n4e/cove
  printf '%s' "$PASS" | gh secret set CODESIGN_P12_PASSWORD -R J0n4e/cove
  echo "Secrets CODESIGN_P12 and CODESIGN_P12_PASSWORD are set on J0n4e/cove."
  echo "Password of $OUT (save it with the file): $PASS"
else
  echo "Created $OUT. Add two GitHub Actions secrets (repo Settings > Secrets and variables > Actions):"
  echo "  base64 -i $OUT | gh secret set CODESIGN_P12 -R J0n4e/cove"
  echo "  gh secret set CODESIGN_P12_PASSWORD -R J0n4e/cove --body '$PASS'"
fi
echo "Keep $OUT and its password in your password manager (losing them means a one-time Keychain prompt for users), then delete $OUT."
