echo "Symlink the Stream Deck helper scripts into ~/.local/bin"
#
# Why: install.sh per-file symlinks bin/nirimaki-* into ~/.local/bin on
# first install, but that loop only runs once. The Stream Deck feature
# adds nine new helpers, and several are invoked by absolute path — the
# Settings menu runs ~/.local/bin/nirimaki-streamdeck-install, the editor
# runs …-set / …-restart / …-detect, and the systemd unit's ExecStart is
# …-streamdeck-start. The `nirimaki` dispatcher also resolves group
# actions from ~/.local/bin. So without these links an existing install
# couldn't even open the installer. Runs ungated (before the service
# migration) so the install entry works even when deckmaster is absent.
#
# Idempotent — rm + ln -s overwrites a stale link, skips a correct one.

NIRIMAKI_REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"
BIN_SRC_DIR="$NIRIMAKI_REPO/bin"
BIN_DST_DIR="$HOME/.local/bin"

relink() {
  local src="$1" dest="$2"
  [[ -f $src ]] || return 0
  if [[ -L $dest && "$(readlink "$dest")" == "$src" ]]; then return 0; fi
  [[ -L $dest || -e $dest ]] && rm -f "$dest"
  chmod +x "$src"
  ln -s "$src" "$dest"
  echo "  linked $dest -> $src"
}

if [[ ! -d $BIN_SRC_DIR ]]; then
  echo "  skip: $BIN_SRC_DIR not present (older repo layout?)"
  exit 0
fi

mkdir -p "$BIN_DST_DIR"
for tool in \
  nirimaki-streamdeck-install   nirimaki-streamdeck-remove \
  nirimaki-streamdeck-start     nirimaki-streamdeck-reload \
  nirimaki-streamdeck-restart   nirimaki-streamdeck-set \
  nirimaki-streamdeck-generate  nirimaki-streamdeck-focus-app \
  nirimaki-streamdeck-detect
do
  relink "$BIN_SRC_DIR/$tool" "$BIN_DST_DIR/$tool"
done
