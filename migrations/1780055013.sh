echo "Install fastfetch + seed its Nirimaki config (config.jsonc + wordmark logo)"
#
# Why: Nirimaki now ships a branded fastfetch config. Fresh installs get
# it natively (packaging.sh §2c installs the package, config.sh seeds the
# files). Existing installs need both the package and the seeded config.
#
# Idempotent: pacman --needed no-ops if fastfetch is present; the seed
# only writes a file when it's absent, so a user's own config/logo is
# never clobbered.

REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"

# 1. Package — fastfetch is in the Arch official repos.
if command -v fastfetch >/dev/null 2>&1; then
  echo "  fastfetch already installed"
else
  echo "  installing fastfetch"
  sudo pacman -S --needed --noconfirm fastfetch || true
fi

# 2. Seed config.jsonc + logo.txt, copy-once (never overwrite user edits).
mkdir -p "$HOME/.config/fastfetch"
for f in config.jsonc logo.txt; do
  dest="$HOME/.config/fastfetch/$f"
  src="$REPO/config/fastfetch/$f"
  if [[ -e $dest ]]; then
    echo "  keep $dest"
  elif [[ -f $src ]]; then
    cp "$src" "$dest" && echo "  seed $dest"
  else
    echo "  skip $dest (missing source $src)"
  fi
done
