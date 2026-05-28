echo "Symlink bin/nirimaki-timezone-set (Settings → Setup → Timezone)"
#
# Why: the new Settings → Setup → Timezone entry runs
# bin/nirimaki-timezone-set in a foot TUI. install.sh per-file symlinks
# bin/nirimaki-* into ~/.local/bin/ on first install, but that loop only
# runs once — existing installs need a re-symlink so the new helper
# resolves on $PATH after `git pull`.
#
# Idempotent — rm + ln -s overwrites a stale link, skips a correct one.

NIRIMAKI_REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"

src="$NIRIMAKI_REPO/bin/nirimaki-timezone-set"
dest="$HOME/.local/bin/nirimaki-timezone-set"

if [[ -f $src ]]; then
  chmod +x "$src"
  if [[ -L $dest && "$(readlink "$dest")" == "$src" ]]; then
    echo "  already linked"
  else
    [[ -L $dest || -e $dest ]] && rm -f "$dest"
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "  linked $dest -> $src"
  fi
else
  echo "  skip: $src not present (older repo layout?)"
fi
