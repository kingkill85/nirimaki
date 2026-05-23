echo "Re-deploy Plymouth logo (terminal-matching proportions + tokyo-night accent)"
#
# Why: assets/plymouth/logo.png was re-rendered with 1:2 cell aspect (matches
# what `cat logo.txt` looks like in a terminal — what nirimaki-update prints
# as its banner) and tinted #7aa2f7 (tokyo-night accent) for visual parity
# between the boot splash, the CLI banner, and the README hero logo.
#
# Bake the new logo into the initramfs; on CachyOS also re-sync the
# Limine-hashed copy (see migration 1779560216 / commit 7d7a63e).

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

if command -v limine-update >/dev/null 2>&1; then
  echo "  re-syncing Limine-hashed initramfs"
  sudo limine-update
fi
