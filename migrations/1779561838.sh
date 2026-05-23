echo "Re-deploy Plymouth logo (1:2.5 aspect — tweak after 1:2 felt too wide)"
#
# Why: the previous logo rebuild at 1:2 cell aspect (commit d748f3d /
# migration 1779561615) looked too wide vs `cat logo.txt` in a real
# JetBrains-Mono terminal cell, which is closer to 1:2.5. Re-rendered
# at CW=16/CH=40 and re-deploying. Same code path as 1779561615 —
# users who already ran that pick up the corrected PNG here.

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
