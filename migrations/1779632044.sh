echo "XWayland bridge: install xwayland-satellite + switch SDDM greeter to Wayland"
#
# Why: niri has no built-in X11 support — X11 clients (Steam, Wine,
# old Electron, GIMP fallback dialogs) need xwayland-satellite as a
# companion bridge process. Without it, $DISPLAY is unset and they
# fail to start. SDDM's default X11 greeter compounded the problem
# by squatting display :0 with an orphan Xorg, pushing satellite to
# :1 and mismatching the DISPLAY env that the new niri default ships
# (see default/niri/autostart.kdl). Switching SDDM to its Wayland
# greeter (the Nirimaki theme is QML — renders natively) frees :0
# and keeps the whole stack Wayland-first.
#
# Two effects on existing boxes:
#   1. xwayland-satellite + xorg-xwayland get pulled in.
#   2. /etc/sddm.conf.d/10-nirimaki.conf gains [General] DisplayServer=wayland.
#      The existing [Theme] block is preserved (we rewrite the whole
#      file — content matches what install/login/sddm.sh now ships).
#
# Takes effect on next SDDM (i.e. next login or reboot). The
# autostart.kdl env block ships DISPLAY=:0, which will be correct
# once SDDM stops squatting it.

# 1. Install the bridge.
if ! pacman -Qq xwayland-satellite >/dev/null 2>&1; then
  echo "  installing xwayland-satellite (pulls xorg-xwayland)"
  sudo pacman -S --needed --noconfirm xwayland-satellite
else
  echo "  xwayland-satellite already installed — skipping"
fi

# 2. Rewrite SDDM conf to add DisplayServer=wayland alongside the
#    existing [Theme] block. Idempotent: matches what install.sh
#    writes today, so re-running is a no-op.
SDDM_CONF=/etc/sddm.conf.d/10-nirimaki.conf
if [[ -f $SDDM_CONF ]] && grep -q '^DisplayServer=wayland' "$SDDM_CONF"; then
  echo "  $SDDM_CONF already has DisplayServer=wayland — skipping"
else
  echo "  rewriting $SDDM_CONF to set DisplayServer=wayland"
  sudo mkdir -p /etc/sddm.conf.d
  sudo tee "$SDDM_CONF" >/dev/null <<'EOF'
[General]
DisplayServer=wayland

[Theme]
Current=nirimaki
EOF
fi

echo "  done — effective on next SDDM start (logout or reboot)"
