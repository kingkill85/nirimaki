echo "Re-deploy UKI splash.bmp (matches Plymouth aspect + #101315 background)"
#
# Why: assets/splash.bmp was the old 800×317 amber wordmark. Re-rendered
# at 1:2.5 cell aspect and tinted #7aa2f7 on a #101315 background — same
# look as the Plymouth LUKS screen, so UKI handoff to Plymouth is seamless.
# Only meaningful on UKI installs (mkinitcpio.d/<kernel>.preset embeds the
# splash into the .efi UKI). Non-UKI boxes get the file deployed but don't
# render it.

set -e

sudo install -Dm644 "$NIRIMAKI_REPO/assets/splash.bmp" /usr/share/nirimaki/splash.bmp
echo "  deployed /usr/share/nirimaki/splash.bmp"

# Re-bake initramfs / UKI if the preset references our splash.
if grep -lq '/usr/share/nirimaki/splash.bmp' /etc/mkinitcpio.d/*.preset 2>/dev/null; then
  echo "  rebuilding UKI (mkinitcpio -P)"
  sudo mkinitcpio -P
  if command -v limine-update >/dev/null 2>&1; then
    sudo limine-update
  fi
else
  echo "  no preset references our splash — skipping mkinitcpio (non-UKI setup)"
fi
