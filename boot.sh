#!/bin/bash
# boot.sh — one-liner bootstrap from a blank Arch box.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingkill85/nirimaki/main/boot.sh)
#
#   or, equivalently (works on minimal Arch where curl IS present but
#   bash's process substitution might trip you up):
#
#   curl -fsSL https://raw.githubusercontent.com/kingkill85/nirimaki/main/boot.sh -o /tmp/boot.sh
#   bash /tmp/boot.sh
#
# What it does:
#   1. Installs git via pacman (Arch "Minimal" archinstall doesn't
#      ship git, and the rest of install.sh needs it).
#   2. Clones the repo to ~/.local/share/nirimaki (the canonical
#      location install.sh expects).
#   3. Hands off to install.sh, which does the actual work.
#
# This avoids the chicken-and-egg of "to update the script that
# installs git, you need git." Hosted via GitHub's raw.githubusercontent
# — no separate infrastructure needed.

set -euo pipefail

REPO_URL="https://github.com/kingkill85/nirimaki.git"
REPO_DIR="$HOME/.local/share/nirimaki"

if [[ $EUID -eq 0 ]]; then
  echo "Don't run boot.sh as root. Run it as your user — sudo is requested when needed." >&2
  exit 1
fi

if [[ ! -f /etc/arch-release ]]; then
  echo "Nirimaki targets Arch Linux — /etc/arch-release not found, refusing." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "==> git not installed — pulling it via pacman"
  sudo pacman -Sy --noconfirm --needed git
fi

if [[ -d $REPO_DIR/.git ]]; then
  echo "==> repo already at $REPO_DIR — refreshing"
  git -C "$REPO_DIR" pull --autostash
else
  echo "==> cloning $REPO_URL → $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

echo
echo "==> handing off to install.sh"
exec bash "$REPO_DIR/install.sh"
