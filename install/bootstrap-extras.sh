#!/bin/bash
# bootstrap-extras.sh — install the standard tools that aren't in pacman
# or AUR. Sourced by install.sh after `pacman -S --needed @base.packages`.
#
# Both tools have official installer scripts; we trust upstream and run
# them. Each one is idempotent (re-runs are safe) and installs to the
# user's home (~/.local/bin/ for claude, ~/.local/bin/ for pi).

set -e

# --- Claude Code (Anthropic official installer) ---
if command -v claude >/dev/null 2>&1; then
  echo "claude already installed at $(command -v claude) — skipping."
else
  echo "Installing claude-code via Anthropic's official installer…"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- pi (earendil-works) ---
# pi's installer runs an interactive picker (install / reinstall /
# uninstall) whenever it can open /dev/tty — which is always true under
# our `script -qefc` log wrapper. Pre-install nodejs + npm via pacman
# (see install/base.packages) so pi's preflight passes, then run the
# installer under `setsid` to detach the controlling tty so it falls
# through to its no-TTY defaults (install fresh / reinstall existing).
if command -v pi >/dev/null 2>&1; then
  echo "pi already installed at $(command -v pi) — skipping."
else
  echo "Installing pi via pi.dev/install.sh (non-interactive)…"
  curl -fsSL https://pi.dev/install.sh -o /tmp/pi-install.sh
  setsid sh /tmp/pi-install.sh </dev/null
  rm -f /tmp/pi-install.sh
fi
