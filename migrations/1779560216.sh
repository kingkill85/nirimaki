echo "Re-sync Limine-hashed initramfs (CachyOS Plymouth theme didn't land on first install)"
#
# Why: CachyOS ships limine-mkinitcpio-hook which stashes the kernel +
# initramfs Limine actually loads under /boot/<machine-id>/<kernel>/.
# That copy is only re-synced via the 90-mkinitcpio-install pacman hook —
# our install.sh's bare `mkinitcpio -P` doesn't trigger pacman hooks, so
# the hashed copy stayed stuck at CachyOS's bootanimation theme while the
# flat /boot/initramfs-*.img got our qs-minimal. Result: nirimaki splash
# at shutdown, CachyOS animation at boot.
#
# install/plymouth.sh now calls limine-update after mkinitcpio -P on fresh
# installs. This migration backfills the same fix for existing boxes.

set -e

if ! command -v limine-update >/dev/null 2>&1; then
  echo "  limine-update not installed — nothing to do (non-CachyOS box)."
  exit 0
fi

echo "  running limine-update — rebuilds the Limine-hashed initramfs"
sudo limine-update
