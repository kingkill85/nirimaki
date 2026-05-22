#!/bin/bash
# install/login/keyring.sh — make gnome-keyring auto-unlock on
# autologin so chromium / webapps / slack / signal never prompt
# for an "Unlock keyring" passphrase.
#
# Mirrors omarchy's install/login/default-keyring.sh +
# install/login/sddm.sh keyring-strip step. The pattern is:
#
#   1. Drop any password-protected keyring files left from a
#      previous session (everything under ~/.local/share/keyrings/).
#   2. Write an empty, unencrypted "Default_keyring" with
#      lock-on-idle=false + lock-after=false so it stays unlocked.
#   3. Strip pam_gnome_keyring.so auth + password hooks from
#      /etc/pam.d/sddm and /etc/pam.d/sddm-autologin so no future
#      session can re-upgrade this into a password-locked keyring.
#
# Idempotent — safe to re-run. Requires sudo for the PAM edits.

set -euo pipefail

KEYRING_DIR="$HOME/.local/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/Default_keyring.keyring"
DEFAULT_FILE="$KEYRING_DIR/default"

echo "== gnome-keyring autologin fix =="

# 1. Stop the running daemon so it doesn't re-write the files we're
#    about to delete (it serializes secrets on signal).
if pgrep -u "$USER" -x gnome-keyring-d >/dev/null; then
  echo "  stopping gnome-keyring-daemon …"
  pkill -u "$USER" -x gnome-keyring-d || true
  # tiny grace period so the daemon actually flushes + exits before
  # we delete the directory it was holding open
  sleep 1
fi

# 2. Wipe any password-locked keyrings left over from before.
if [[ -d $KEYRING_DIR ]]; then
  shopt -s nullglob
  for f in "$KEYRING_DIR"/*.keyring "$KEYRING_DIR"/default "$KEYRING_DIR"/user.keystore; do
    rm -f "$f"
  done
  shopt -u nullglob
fi

# 3. Recreate as an empty, unencrypted, never-locks Default_keyring.
mkdir -p "$KEYRING_DIR"
cat > "$KEYRING_FILE" <<EOF
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
printf '%s\n' 'Default_keyring' > "$DEFAULT_FILE"

chmod 700 "$KEYRING_DIR"
chmod 600 "$KEYRING_FILE"
chmod 644 "$DEFAULT_FILE"

echo "  ✓ wrote $KEYRING_FILE (empty, unencrypted, never relocks)"

# 4. Strip pam_gnome_keyring lines from SDDM PAM stacks so no future
#    login pass re-creates an encrypted login.keyring alongside ours.
#    Vanilla Arch ships both `auth` and `-auth` variants depending on
#    the file; the four sed exprs cover both.
strip_pam() {
  local file="$1"
  [[ -f $file ]] || return 0
  if ! sudo grep -q pam_gnome_keyring "$file" 2>/dev/null; then
    echo "  ✓ $file already clean"
    return 0
  fi
  echo "  patching $file (backup at $file.nirimaki-bak) …"
  sudo cp -n "$file" "$file.nirimaki-bak"
  sudo sed -i \
    -e '/-auth.*pam_gnome_keyring\.so/d' \
    -e '/-password.*pam_gnome_keyring\.so/d' \
    -e '/^auth.*pam_gnome_keyring\.so/d' \
    -e '/^password.*pam_gnome_keyring\.so/d' \
    -e '/^session.*pam_gnome_keyring\.so/d' \
    "$file"
}
strip_pam /etc/pam.d/sddm
strip_pam /etc/pam.d/sddm-autologin

echo
echo "✓ Done. Log out + back in, or relaunch the apps that were"
echo "  prompting — chromium webapps will pick up the new keyring"
echo "  the next time they read a secret."
