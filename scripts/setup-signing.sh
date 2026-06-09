#!/usr/bin/env bash
set -euo pipefail

# One-time setup: create a self-signed code signing certificate in the user's
# login keychain so JVoice's installed binary has a stable signing identity
# across rebuilds. macOS TCC pins permissions to the signing identity — with
# a stable cert, granted permissions survive rebuilds.
#
# Usage: scripts/setup-signing.sh
# Idempotent: re-running is a no-op if the cert is already set up.
#
# Reuses the "JVoice Self-Signed" cert name, so an identity already present
# in the login keychain (e.g. from a prior install) is detected and reused.
#
# PREREQUISITE: Homebrew OpenSSL 3.x with the PKCS12 `-legacy` flag.
#   Install via:  brew install openssl@3
# macOS ships LibreSSL, which lacks `-legacy`, so the system `openssl` cannot
# produce the RC2-40-CBC PKCS12 that `security import` requires. This script
# searches the Homebrew install paths below; without brew OpenSSL 3 it exits
# with an actionable error.

CERT_NAME="JVoice Self-Signed"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning login.keychain | grep -q "$CERT_NAME"; then
    echo "Code signing identity '$CERT_NAME' already exists in login keychain."
    echo "Run scripts/install.sh to use it."
    exit 0
fi

echo "==> Creating self-signed code signing certificate..."

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# macOS `security import` needs the legacy PKCS12 cipher (RC2-40-CBC) that
# OpenSSL 3 hid behind the `-legacy` flag and LibreSSL doesn't support at all.
# Pick a binary that has the flag.
OPENSSL=""
for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /opt/homebrew/opt/openssl/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do
    if [ -x "$candidate" ] && "$candidate" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
        OPENSSL="$candidate"
        break
    fi
done
if [ -z "$OPENSSL" ]; then
    echo "ERROR: Need an OpenSSL 3.x binary with the -legacy flag for PKCS12 export."
    echo "Install via: brew install openssl@3"
    exit 1
fi
echo "    Using $OPENSSL"

cat > "$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = req_dn
x509_extensions = v3_ext
prompt = no

[ req_dn ]
CN = $CERT_NAME

[ v3_ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning, 1.2.840.113635.100.6.1.13
EOF

"$OPENSSL" req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -config "$TMP/cert.conf"

"$OPENSSL" pkcs12 -legacy -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -password pass:jvoice -name "$CERT_NAME"

echo "==> Importing into login keychain..."
security import "$TMP/identity.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -P jvoice

echo "==> Setting key partition list to allow codesign access..."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$LOGIN_KEYCHAIN" 2>/dev/null || \
    echo "   (Couldn't set partition list non-interactively — codesign may prompt the first time. That's OK; click 'Always Allow'.)"

echo
echo "Done. JVoice signing identity is now in your login keychain."
echo "Run scripts/install.sh — future rebuilds will keep your TCC permissions intact."
