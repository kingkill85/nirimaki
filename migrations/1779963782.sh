echo "Install gnome-keyring (secret-service daemon for GUI credential storage)"
#
# Why: Niri ships no secret-service daemon, so any GTK app that calls
# org.freedesktop.secrets (Nautilus storing a LUKS passphrase,
# NetworkManager saving WiFi/VPN passwords, libsecret in general) fails
# with "The name is not activatable" — DBus has no provider to start.
# default/niri/autostart.kdl now spawns gnome-keyring-daemon every
# session; this migration backfills the package on existing installs.
#
# Idempotent: pacman -S --needed is a no-op if already installed; the
# daemon launch is gated on (a) not already running and (b) a graphical
# session being present, so running this from a TTY won't fail.

if ! pacman -Qq gnome-keyring >/dev/null 2>&1; then
  echo "  installing gnome-keyring"
  sudo pacman -S --needed --noconfirm gnome-keyring
else
  echo "  gnome-keyring already installed"
fi

if [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && ! pgrep -fx 'gnome-keyring-daemon --start --components=secrets,ssh' >/dev/null 2>&1 \
   && ! pgrep -x gnome-keyring-d >/dev/null 2>&1; then
  echo "  starting gnome-keyring-daemon for the current session"
  gnome-keyring-daemon --start --components=secrets,ssh >/dev/null 2>&1 || true
fi
