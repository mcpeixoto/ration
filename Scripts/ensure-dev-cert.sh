#!/bin/bash
#
# Creates a stable "Ration Development" code-signing identity if one is missing.
#
# macOS ties keychain "Always Allow" to the app's code signature. An ad-hoc
# signature changes every build, so the grant is void each time. Signing with
# Developer ID instead asks for the login-keychain password on every codesign,
# because that private key is protected.
#
# A self-signed identity in its own keychain, unlocked with a password this
# script knows, is stable across builds and never asks for the Mac password.

set -euo pipefail

NAME="Ration Development"
KEYCHAIN="$HOME/Library/Keychains/ration-dev.keychain-db"
PASSWORD="ration-dev-signing"

unlock() {
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || true
}

if [ -f "$KEYCHAIN" ]; then
    unlock
    if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$NAME"; then
        exit 0
    fi
    # A previous run left an empty or unpaired keychain. Start clean.
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
fi

echo "==> Creating $NAME code-signing identity"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/codesign.cnf" <<'EOF'
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
prompt             = no
x509_extensions    = codesign_ext

[ req_distinguished_name ]
CN = Ration Development
O = Ration

[ codesign_ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Homebrew OpenSSL 3 for the cert; macOS LibreSSL for the p12, because
# Security.framework rejects OpenSSL 3's default PKCS#12 MAC.
OPENSSL="${OPENSSL:-/opt/homebrew/bin/openssl}"
[ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl)"
LIBRESSL=/usr/bin/openssl

"$OPENSSL" req -new -x509 -days 3650 -nodes \
    -config "$TMP/codesign.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem"

"$LIBRESSL" pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/ration-dev.p12" -passout pass:"$PASSWORD" \
    -name "$NAME"

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
unlock
security import "$TMP/ration-dev.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security -A
# find-identity -p codesigning ignores untrusted certs. User-scope trust,
# not the admin store, so this should not ask for the Mac password.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" \
    >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

EXISTING="$(security list-keychains -d user | tr -d '" ')"
if ! printf '%s\n' "$EXISTING" | grep -q 'ration-dev.keychain'; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $EXISTING
fi

if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$NAME"; then
    echo "error: $NAME was imported but is not a valid codesigning identity" >&2
    security find-identity -v -p codesigning "$KEYCHAIN" >&2 || true
    exit 1
fi

echo "==> Created $NAME (codesign will not ask for your Mac password)"
