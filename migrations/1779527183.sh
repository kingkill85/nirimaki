echo "Re-sync Plymouth theme assets (entry.png + bullet.png) + rebuild initramfs"
#
# Why: the qs-minimal Plymouth theme references entry.png and bullet.png
# but those assets were missing from the repo. Result: at LUKS unlock
# (and any other Plymouth password prompt), the input box and typed
# bullets weren't drawn — users typed their password blind.
#
# Fix is two new PNG assets under assets/plymouth/; this migration
# re-copies the whole plymouth dir and rebuilds the initramfs so the
# theme inside the initrd is up-to-date.
#
# Idempotent: install -m644 overwrites in place; mkinitcpio -P is
# always safe to re-run.

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
