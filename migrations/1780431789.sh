echo "Install the Stream Deck systemd user service (if deckmaster is present)"
#
# Why: the Stream Deck used to autostart via niri's autostart.kdl, with
# no recovery if deckmaster crashed. It's now owned by a systemd user
# unit (auto-restart on failure). That unit lives under
# ~/.config/systemd/user/, which a plain `git pull` can't place — and the
# old autostart line is gone, so without this an existing install would
# lose its deck on next login. Only relevant to users who actually have
# the daemon, so we skip otherwise.
#
# Idempotent: install overwrites in place; enable/daemon-reload are safe
# to repeat.

set -e

if ! command -v deckmaster >/dev/null 2>&1; then
  echo "  No deckmaster — skipping (run 'nirimaki streamdeck install' to enable)."
  exit 0
fi

REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"
unit_src="$REPO/assets/systemd/nirimaki-streamdeck.service"
unit_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/nirimaki-streamdeck.service"

if [[ ! -f $unit_src ]]; then
  echo "  Unit source missing at $unit_src — skipping."
  exit 0
fi

install -Dm 644 "$unit_src" "$unit_dst"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now nirimaki-streamdeck.service 2>/dev/null || true
echo "  Installed + enabled nirimaki-streamdeck.service."
