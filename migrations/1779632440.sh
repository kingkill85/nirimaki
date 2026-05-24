echo "Strip blueman (CachyOS preinstall + earlier install.sh shipped it)"
#
# Why: blueman runs a GTK applet that adds a *second* bluetooth tray
# icon alongside Nirimaki's own Bluetooth Bar widget, and competes
# with bluetui (which the bar's bluetooth click handler and the
# SettingsMenu's Setup → Bluetooth entry both launch). Older
# install.sh versions also actively installed blueman as part of
# the compositor packages list — this migration backfills the
# removal for both that historical install and CachyOS preinstalls.
# Conditional, so non-CachyOS / freshly-installed boxes are a no-op.

if ! pacman -Qq blueman >/dev/null 2>&1; then
  echo "  blueman not installed — skipping"
  exit 0
fi

echo "  stopping blueman applet (if running)"
systemctl --user stop app-blueman@autostart.service 2>/dev/null || true
pkill -x blueman-applet 2>/dev/null || true
pkill -x blueman-tray 2>/dev/null || true

echo "  removing blueman"
sudo pacman -R --noconfirm blueman
