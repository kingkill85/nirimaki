echo "Re-sync Plymouth theme assets + rebuild initramfs"
#
# Why: the Plymouth theme files live at /usr/share/plymouth/themes/
# qs-minimal/, copied (not symlinked) during install.sh. A `git pull`
# alone doesn't refresh them, and Plymouth itself reads from the
# initramfs — so even after re-copying, mkinitcpio -P is needed.
#
# This migration corresponds to the logo-scaling fix in commit
# 87413a6 ("plymouth — scale logo to 25% of screen width"). Re-copies
# every file under assets/plymouth/ and rebuilds the initramfs.
#
# Idempotent: install -m644 overwrites in place; mkinitcpio -P is
# always safe to re-run.

set -e

THEME_DIR=/usr/share/plymouth/themes/qs-minimal

# Nothing to do if Plymouth was never installed on this box.
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
