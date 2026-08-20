#!/bin/bash
# One-time creation of the persistent local identity used by every personal build.
# The identity lives in a project-only keychain, never in the user's login keychain.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Keyboop Personal"
KEYCHAIN="$PWD/.personal-signing.keychain-db"
PASS_FILE="$PWD/.personal-signing-keychain-password"

ensure_in_search_list() {
  if security list-keychains -d user | tr -d ' "' | grep -Fxq "$KEYCHAIN"; then return; fi
  local existing=() entry
  while IFS= read -r entry; do
    entry="${entry#*\"}"
    entry="${entry%%\"*}"
    [ -n "$entry" ] && existing+=("$entry")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "$KEYCHAIN" "${existing[@]}"
}

if [ -f "$KEYCHAIN" ] && [ -f "$PASS_FILE" ]; then
  KEYCHAIN_PASS=$(cat "$PASS_FILE")
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  ensure_in_search_list
  if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$IDENTITY\""; then
    echo "✓ Signing identity \"$IDENTITY\" already exists in the project keychain"
    exit 0
  fi
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
P12_PASS=$(openssl rand -hex 24)
KEYCHAIN_PASS=$(openssl rand -hex 32)
umask 077
printf '%s' "$KEYCHAIN_PASS" > "$PASS_FILE"

if [ -f "$KEYCHAIN" ]; then
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
fi
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -subj "/CN=$IDENTITY/O=Personal Build/OU=Code Signing" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem"
openssl pkcs12 -export -legacy -name "$IDENTITY" \
  -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
  -passout "pass:$P12_PASS" -out "$TMP_DIR/identity.p12"

security import "$TMP_DIR/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
ensure_in_search_list

security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$IDENTITY\""
echo "✓ Created project-only signing identity \"$IDENTITY\""
echo "  Keep both .personal-signing files to preserve macOS permissions across rebuilds."
