echo "Install polkit-gnome (auth agent for GUI privilege prompts)"
#
# Why: Niri ships no polkit authentication agent, so GUI apps that
# trigger polkit (Nautilus unlocking an internal LUKS drive, NM VPN
# secret prompts, GNOME Disks operations, …) silently fail with
# "not authorized" because there's no front-end to draw the password
# dialog. default/niri/autostart.kdl now spawns the polkit-gnome agent
# every session; this migration backfills the package on existing
# installs so the spawn line has a binary to run.
#
# Idempotent: pacman -S --needed is a no-op if already installed; the
# agent launch is gated on (a) not already running and (b) a graphical
# session being present, so running this from a TTY won't fail.

if ! pacman -Qq polkit-gnome >/dev/null 2>&1; then
  echo "  installing polkit-gnome"
  sudo pacman -S --needed --noconfirm polkit-gnome
else
  echo "  polkit-gnome already installed"
fi

AGENT=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
if [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && ! pgrep -fx "$AGENT" >/dev/null 2>&1; then
  echo "  starting polkit-gnome agent for the current session"
  setsid -f "$AGENT" >/dev/null 2>&1 || true
fi
