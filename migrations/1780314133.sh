echo "Install Elgato Stream Deck udev rule (if deckmaster / a device is present)"
#
# Why: the uaccess udev rule lives at /etc/udev/rules.d/, which a plain
# `git pull` can't place. Ships with the new optional Stream Deck
# control feature (deckmaster wrapper). Only relevant to users who have
# the daemon installed or a device plugged in, so we skip otherwise to
# avoid touching /etc for everyone.
#
# Idempotent: install -m644 overwrites in place; udevadm reload/trigger
# are always safe.

set -e

RULE_SRC="$NIRIMAKI_REPO/assets/udev/99-nirimaki-streamdeck.rules"
RULE_DST=/etc/udev/rules.d/99-nirimaki-streamdeck.rules

# Skip unless deckmaster is installed or an Elgato device (0fd9) is attached.
have_deck() {
  local f
  for f in /sys/bus/usb/devices/*/idVendor; do
    [[ -r $f ]] || continue
    [[ $(< "$f") == "0fd9" ]] && return 0
  done
  return 1
}
if ! command -v deckmaster >/dev/null 2>&1 && ! have_deck; then
  echo "  No deckmaster and no Stream Deck attached — skipping."
  echo "  (run 'nirimaki streamdeck install' later to enable it.)"
  exit 0
fi

if [[ ! -f $RULE_SRC ]]; then
  echo "  Rule source missing at $RULE_SRC — skipping."
  exit 0
fi

sudo install -m 644 "$RULE_SRC" "$RULE_DST"
sudo udevadm control --reload
sudo udevadm trigger
echo "  Installed $RULE_DST — replug the Stream Deck once to apply."
