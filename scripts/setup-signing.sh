#!/usr/bin/env bash
# Run once per Mac:  scripts/setup-signing.sh
#
# Creates a private, self-signed code-signing certificate for F2L. build-app.sh then signs every build with it, so
# macOS keeps F2L's Screen Recording and Accessibility permissions across rebuilds instead of asking again each time.
# Grant those permissions once more after the first build signed this way.
#
# Everything is kept in ~/Library/Application Support/F2L/Signing (see local-signing.sh); delete that folder to undo.
# If you have an Apple Development certificate, you can skip this and set SIGN_IDENTITY instead (SETUP.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/local-signing.sh"

if [[ -f "$F2L_SIGNING_KEYCHAIN" ]]; then
  f2l_signing_ready # unlocks it again, e.g. after a restart
  echo "F2L's signing certificate is ready: $F2L_SIGNING_KEYCHAIN"
  exit 0
fi

mkdir -p "$F2L_SIGNING_DIR"
chmod 700 "$F2L_SIGNING_DIR"
if [[ -z "$F2L_SIGNING_PASSWORD" ]]; then
  F2L_SIGNING_PASSWORD="$(/usr/bin/openssl rand -hex 32)"
fi
(umask 077; printf '%s\n' "$F2L_SIGNING_PASSWORD" > "$F2L_SIGNING_PASSWORD_FILE")
chmod 600 "$F2L_SIGNING_PASSWORD_FILE"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/certificate.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $F2L_SIGNING_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS's own OpenSSL writes a PKCS#12 file that `security import` can read (Homebrew's OpenSSL 3 doesn't by default).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/certificate.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" -name "$F2L_SIGNING_NAME" \
  -out "$WORK/identity.p12" -passout "pass:$F2L_SIGNING_PASSWORD"

security create-keychain -p "$F2L_SIGNING_PASSWORD" "$F2L_SIGNING_KEYCHAIN"
security set-keychain-settings "$F2L_SIGNING_KEYCHAIN" # no automatic locking
security unlock-keychain -p "$F2L_SIGNING_PASSWORD" "$F2L_SIGNING_KEYCHAIN"
security import "$WORK/identity.p12" -k "$F2L_SIGNING_KEYCHAIN" -P "$F2L_SIGNING_PASSWORD" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without a password dialog on every build.
security set-key-partition-list -S apple-tool:,apple: -s -k "$F2L_SIGNING_PASSWORD" "$F2L_SIGNING_KEYCHAIN" >/dev/null
# Lets codesign find the certificate by name (SIGN_IDENTITY="F2L Local Signing").
KEYCHAINS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line#\"}"; line="${line%\"}"
  [[ -n "$line" ]] && KEYCHAINS+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${KEYCHAINS[@]}" "$F2L_SIGNING_KEYCHAIN"

echo "Created F2L's signing certificate in $F2L_SIGNING_KEYCHAIN"
echo "Next: build with SIGN_IDENTITY=\"$F2L_SIGNING_NAME\" scripts/build-app.sh, open F2L and grant its permissions once more."
