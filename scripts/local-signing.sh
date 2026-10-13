#!/usr/bin/env bash
# Sourced by setup-signing.sh: where F2L's private signing certificate lives on this Mac.
# One keychain file holds it; it is listed in your keychains so codesign can find it, and signs nothing but F2L builds.
F2L_SIGNING_DIR="$HOME/Library/Application Support/F2L/Signing"
F2L_SIGNING_KEYCHAIN="$F2L_SIGNING_DIR/F2L-signing.keychain-db"
F2L_SIGNING_NAME="F2L Local Signing"
# Passwords are machine-specific and kept outside the repository, readable only by this user.
F2L_SIGNING_PASSWORD_FILE="$F2L_SIGNING_DIR/keychain-password"
F2L_SIGNING_PASSWORD="${F2L_SIGNING_PASSWORD:-}"
if [[ -z "$F2L_SIGNING_PASSWORD" && -f "$F2L_SIGNING_PASSWORD_FILE" ]]; then
  F2L_SIGNING_PASSWORD="$(cat "$F2L_SIGNING_PASSWORD_FILE")"
fi

# Unlocks the keychain if it exists. Returns 1 when setup-signing.sh hasn't been run.
f2l_signing_ready() {
  [[ -f "$F2L_SIGNING_KEYCHAIN" ]] || return 1
  if [[ -z "$F2L_SIGNING_PASSWORD" ]]; then
    echo "F2L signing password is missing. Set F2L_SIGNING_PASSWORD locally to unlock this existing keychain." >&2
    return 1
  fi
  security unlock-keychain -p "$F2L_SIGNING_PASSWORD" "$F2L_SIGNING_KEYCHAIN"
}
