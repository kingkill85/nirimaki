echo "Gaming layer: gamemode + mangohud (+ cachyos-gaming-meta on CachyOS)"
#
# Why: earlier nirimaki-steam-install only installed Steam + matching
# lib32 GPU drivers, and left gamemode/mangohud/Proton-CachyOS as
# manual TODOs. nirimaki-steam-install now bundles them. Backfill for
# users who installed Steam under the old helper. Skips entirely if
# Steam was never installed (no point pulling lib32-gamemode on a
# Nirimaki box that doesn't game).

if ! pacman -Qq steam >/dev/null 2>&1; then
  echo "  steam not installed — skipping gaming layer backfill"
  exit 0
fi

echo "  installing gamemode + mangohud (64 + 32 bit)"
sudo pacman -S --needed --noconfirm \
  gamemode lib32-gamemode \
  mangohud lib32-mangohud

# CachyOS-only: their meta-bundle (Proton-CachyOS + Wine-CachyOS-opt +
# umu-launcher + protontricks/winetricks + lib32 audio/GL plumbing).
# The package only exists in the cachyos repo, so the ID guard keeps
# this a no-op on vanilla Arch.
if [[ -r /etc/os-release ]] && grep -q '^ID=cachyos' /etc/os-release; then
  echo "  CachyOS detected — installing cachyos-gaming-meta"
  sudo pacman -S --needed --noconfirm cachyos-gaming-meta
fi
