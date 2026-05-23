echo "Re-sync Plymouth theme assets (revert logo-scaling regression) + rebuild initramfs"
#
# Why: commit 87413a6 added Math/scaling code to qs-minimal.script that
# turned out to break Plymouth's script interpreter on at least one box —
# password callbacks never registered, so users at LUKS unlock saw the
# splash with no input prompt. Reverting the script + ship the original
# pre-scaled 5.3 KB logo.png that doesn't need runtime scaling.
#
# Re-runs everything under assets/plymouth/ into the system theme dir
# and rebuilds the initramfs (Plymouth reads from initrd at boot).

set -e

THEME_DIR=/usr/share/plymouth/themes/qs-minimal

if [[ ! -d $THEME_DIR ]]; then
  echo "  Plymouth theme dir not present — skipping (Plymouth not installed)."
  exit 0
fi

for src in "$NIRIMAKI_REPO"/assets/plymouth/*; do
  [[ -f $src ]] || continue
  sudo install -m 644 "$src" "$THEME_DIR/$(basename "$src")"
done

echo "  rebuilding initramfs (mkinitcpio -P) — can take a minute"
sudo mkinitcpio -P
