echo "Re-deploy Plymouth qs-minimal (pure black background to match UKI splash)"
#
# Why: qs-minimal.script used #101315 (dark grey) which made the boot-stub
# handoff look like a coloured card on black. Pure black removes that
# transition. Asset diff is qs-minimal.script only, but we redeploy the
# whole theme dir for idempotence and re-bake the initramfs so the change
# actually reaches the boot Plymouth (the running system's Plymouth only
# matters at shutdown — initramfs is what shows at LUKS unlock).

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
