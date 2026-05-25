echo "Switch network stack to NetworkManager (Group F)"
#
# Why: Group F of the Quickshell-migration plan ships the network panel
# that talks to NetworkManager via DBus (Quickshell.Networking). Earlier
# installs enabled systemd-networkd; running both at once races for
# interfaces (IP flapping, DNS clobbering, conflicting routes), so this
# migration flips the active manager to NM.
#
# What it does:
#   1. Installs `networkmanager` if missing.
#   2. Disables + stops systemd-networkd.service (and its socket).
#   3. Enables + starts NetworkManager.service.
#   4. Bails early if NM is already the active manager.
#
# Idempotent: safe to re-run.

# The networkd family is larger than the obvious .service + .socket
# duo. On current systemd (CachyOS, vanilla Arch as of late 2025+) we
# also have varlink + resolve-hook sockets, plus the wait-online
# helper. Disabling only some leaves the rest as triggers that
# re-activate networkd.service immediately.
NETWORKD_UNITS=(
  systemd-networkd.service
  systemd-networkd.socket
  systemd-networkd-varlink.socket
  systemd-networkd-varlink-metrics.socket
  systemd-networkd-resolve-hook.socket
  systemd-networkd-wait-online.service
)

# Step 0 — if NM is already managing and every networkd unit is off
# (inactive AND disabled), we're done.
nm_ok=true
systemctl is-active --quiet NetworkManager.service || nm_ok=false
networkd_off=true
for u in "${NETWORKD_UNITS[@]}"; do
  if systemctl is-enabled --quiet "$u" 2>/dev/null \
     || systemctl is-active  --quiet "$u" 2>/dev/null; then
    networkd_off=false
    break
  fi
done
if $nm_ok && $networkd_off; then
  echo "  NetworkManager already active, networkd family already off — nothing to do."
  exit 0
fi

# Step 1 — package.
if ! pacman -Q networkmanager >/dev/null 2>&1; then
  echo "  installing networkmanager…"
  sudo pacman -S --needed --noconfirm networkmanager
fi

# Step 2 — disable + stop the whole networkd family. We list each unit
# individually; passing them all at once would short-circuit on the
# first "unit not found" on minimal systems.
echo "  disabling networkd family…"
for u in "${NETWORKD_UNITS[@]}"; do
  sudo systemctl disable --now "$u" 2>/dev/null || true
done

# Step 3 — enable NM. Starting NM while networkd is also live would
# cause exactly the conflict we're avoiding; networkd is already down
# from step 2, so it's safe to bring NM up next.
echo "  enabling NetworkManager…"
sudo systemctl enable --now NetworkManager.service

# Step 4 — sanity. A failed enable bubbles up via set -e in the runner;
# explicit check here lets us print a clearer message.
if ! systemctl is-active --quiet NetworkManager.service; then
  echo "  NetworkManager failed to start — check 'systemctl status NetworkManager.service'"
  exit 1
fi

# Heads-up about dhcpcd, which CachyOS sometimes leaves enabled. NM
# spawns its own DHCP client, so a parallel dhcpcd would race it.
if systemctl is-enabled --quiet dhcpcd.service 2>/dev/null \
   || systemctl is-active  --quiet dhcpcd.service 2>/dev/null; then
  echo "  ⚠  dhcpcd.service is enabled — it will race NetworkManager for DHCP."
  echo "     Consider:  sudo systemctl disable --now dhcpcd.service"
fi
