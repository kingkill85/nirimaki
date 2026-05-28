echo "Backfill /var/lib/nirimaki/polkit-markers/ for existing VPN polkit rules"
#
# Why: nirimaki-feature-state now detects "is the wireguard/openvpn
# polkit rule installed?" by checking a user-readable marker at
# /var/lib/nirimaki/polkit-markers/<rule-name>. The rule itself lives
# in /etc/polkit-1/rules.d/ which is root:polkitd 0750 — regular users
# can't stat files inside without sudo.
#
# Older installs already wrote the polkit rule but never the marker.
# This migration creates the dir and touches a marker for whichever
# rule(s) are present, so wireguard_configured / openvpn_configured
# correctly report true on first refresh after upgrade.
#
# Idempotent — uses `install` (creates dir mode 0755, marker mode 0644).

if [[ $EUID -ne 0 ]]; then
  sudo install -d -m 0755 /var/lib/nirimaki/polkit-markers
else
  install -d -m 0755 /var/lib/nirimaki/polkit-markers
fi

for rule in 50-nirimaki-wireguard.rules 50-nirimaki-openvpn.rules; do
  if sudo test -e "/etc/polkit-1/rules.d/$rule"; then
    sudo install -m 0644 /dev/null "/var/lib/nirimaki/polkit-markers/$rule"
    echo "  marker for $rule"
  fi
done

# Refresh state.json so the new bits are emitted immediately.
if [[ -x $HOME/.local/bin/nirimaki-feature-state ]]; then
  "$HOME/.local/bin/nirimaki-feature-state" >/dev/null 2>&1 || true
fi
