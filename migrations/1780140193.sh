echo "Ensure gnome-themes-extra so GTK apps follow dark/light themes"
#
# Why: nirimaki-theme-set now names the genuine `Adwaita-dark` theme for
# dark themes (instead of only flipping the prefer-dark hint), so GTK3
# CSD apps that override the hint from their own prefs — notably Remmina
# — render dark too. That theme ships with gnome-themes-extra. Fresh
# installs already get it (packaging.sh), but installs predating that
# line fall back to the hint-only path and miss the fix until the
# package is present.
#
# Idempotent: pacman --needed no-ops when already installed.

echo "  installing gnome-themes-extra (if missing)"
sudo pacman -S --needed --noconfirm gnome-themes-extra || true
