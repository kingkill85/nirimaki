#!/bin/bash
# install/login/sddm.sh — install the Nirimaki SDDM theme.
#
# Three steps, idempotent, requires sudo:
#   1. Copy default/sddm/nirimaki/ → /usr/share/sddm/themes/nirimaki/
#      (just the QML + .conf + .desktop — no PNG assets to ship).
#   2. Hand state/ to the current user so nirimaki-sddm-sync can write
#      to it without sudo on every theme switch.
#   3. Write /etc/sddm.conf.d/10-nirimaki.conf with [Theme]
#      Current=nirimaki. Kept additive — autologin.conf (if present) is
#      left alone.
#
# After this runs, call `nirimaki-sddm-sync` once to seed state/ with
# the active theme. From then on `nirimaki-theme-set` does that for you.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
THEME_SRC="$REPO_DIR/default/sddm/nirimaki"
THEME_DST="/usr/share/sddm/themes/nirimaki"

[[ -d $THEME_SRC ]] || { echo "missing $THEME_SRC" >&2; exit 1; }

echo "== Nirimaki SDDM theme install =="

# 1. Theme files.
echo "  installing theme to $THEME_DST …"
sudo mkdir -p "$THEME_DST/state"
sudo cp -f "$THEME_SRC/Main.qml"          "$THEME_DST/Main.qml"
sudo cp -f "$THEME_SRC/theme.conf"        "$THEME_DST/theme.conf"
sudo cp -f "$THEME_SRC/metadata.desktop"  "$THEME_DST/metadata.desktop"

# 2. state/ owned by the user so the sync helper runs unprivileged.
#    Same trade-off as /etc/chromium/policies/managed/ in phase I.
sudo chown -R "$USER:$USER" "$THEME_DST/state"
sudo chmod 755 "$THEME_DST/state"

# 3. SDDM picks the theme via a separate conf file so existing
#    autologin.conf is left alone.
echo "  writing /etc/sddm.conf.d/10-nirimaki.conf …"
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-nirimaki.conf >/dev/null <<'EOF'
[Theme]
Current=nirimaki
EOF

echo
echo "✓ theme installed"
echo "✓ state/ owned by $USER"
echo "✓ SDDM configured to use 'nirimaki'"
echo
echo "Now seed the state with the active theme:"
echo "    nirimaki-sddm-sync"
echo
echo "Preview without logging out:"
echo "    sddm-greeter-qt6 --test-mode --theme $THEME_DST"
