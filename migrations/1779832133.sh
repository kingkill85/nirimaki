echo "Re-symlink VPN provider plumbing (vpns.d samples + bin/nirimaki-{wireguard,openvpn,pia,netextender}-{install,remove})"
#
# Why: Phase T+1 added two fresh VPN provider templates (wireguard,
# openvpn), updated tailscale/pia/netextender with install/fields
# metadata, and added 8 new install/remove helper scripts. install.sh
# per-file symlinks `config/nirimaki/**/*` into `~/.config/nirimaki/`
# and `bin/nirimaki-*` into `~/.local/bin/` on first install — but
# those loops only run once. Existing installs need a re-symlink so
# the new files appear in both directories.
#
# Idempotent — `_link_file` style (rm + ln -s) overwrites stale
# symlinks and skips already-correct ones.

NIRIMAKI_REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"
relink() {
  # $1 = src absolute path, $2 = dest absolute path
  local src="$1" dest="$2"
  if [[ -L $dest && "$(readlink "$dest")" == "$src" ]]; then
    return 0
  fi
  if [[ -L $dest || -e $dest ]]; then
    rm -f "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "  linked $dest -> $src"
}

# 1. vpns.d/*.json.sample → ~/.config/nirimaki/vpns.d/
SRC_DIR="$NIRIMAKI_REPO/config/nirimaki/vpns.d"
DST_DIR="$HOME/.config/nirimaki/vpns.d"
if [[ -d $SRC_DIR ]]; then
  mkdir -p "$DST_DIR"
  shopt -s nullglob
  for src in "$SRC_DIR"/*.json.sample; do
    relink "$src" "$DST_DIR/$(basename "$src")"
  done
  shopt -u nullglob
else
  echo "  skip: $SRC_DIR not present (older repo layout?)"
fi

# 2. bin/nirimaki-{wireguard,openvpn,pia,netextender}-{install,remove}
#    + nirimaki-vpn-provider-helpers → ~/.local/bin/
BIN_SRC_DIR="$NIRIMAKI_REPO/bin"
BIN_DST_DIR="$HOME/.local/bin"
if [[ -d $BIN_SRC_DIR ]]; then
  mkdir -p "$BIN_DST_DIR"
  for tool in \
    nirimaki-vpn-provider-helpers \
    nirimaki-wireguard-install nirimaki-wireguard-remove \
    nirimaki-openvpn-install   nirimaki-openvpn-remove \
    nirimaki-pia-install       nirimaki-pia-remove \
    nirimaki-netextender-install nirimaki-netextender-remove
  do
    src="$BIN_SRC_DIR/$tool"
    [[ -f $src ]] || continue
    chmod +x "$src"
    relink "$src" "$BIN_DST_DIR/$tool"
  done
else
  echo "  skip: $BIN_SRC_DIR not present (older repo layout?)"
fi
