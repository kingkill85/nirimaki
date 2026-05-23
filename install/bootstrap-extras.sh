#!/bin/bash
# bootstrap-extras.sh — install the standard tools that aren't in pacman
# or AUR. Sourced by install.sh after `pacman -S --needed @base.packages`.
#
# Both tools have official installer scripts; we trust upstream and run
# them. Each one is idempotent (re-runs are safe) and installs to the
# user's home (~/.local/bin/ for claude, ~/.local/bin/ for pi).
#
# We source helpers.sh so claude/pi installers run through `run_quiet`
# — keeps them in line with the rest of the install's heartbeat-only
# output style instead of dumping their own ANSI animations.

set -e

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Make sure ~/.local/bin is on PATH for the duration of this script and
# beyond — claude/pi install there, and verify.sh runs later in the
# same install.sh process.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# --- Claude Code (Anthropic official installer) ---
if command -v claude >/dev/null 2>&1; then
  ok "claude already installed at $(command -v claude)"
else
  info "Installing claude-code via Anthropic's installer"
  curl -fsSL https://claude.ai/install.sh -o /tmp/nirimaki-claude-install.sh
  run_quiet "claude-code installer" -- bash /tmp/nirimaki-claude-install.sh
  rm -f /tmp/nirimaki-claude-install.sh
fi

# --- pi (earendil-works) ---
# pi's installer runs an interactive picker (install / reinstall /
# uninstall) whenever it can open /dev/tty — which is always true under
# our `script -qefc` log wrapper. Pre-install nodejs + npm via pacman
# (see install/base.packages) so pi's preflight passes, then run the
# installer under `setsid` to detach the controlling tty so it falls
# through to its no-TTY defaults (install fresh / reinstall existing).
if command -v pi >/dev/null 2>&1; then
  ok "pi already installed at $(command -v pi)"
else
  info "Installing pi via pi.dev/install.sh (non-interactive)"
  curl -fsSL https://pi.dev/install.sh -o /tmp/nirimaki-pi-install.sh
  run_quiet "pi installer" -- bash -c "setsid sh /tmp/nirimaki-pi-install.sh </dev/null"
  rm -f /tmp/nirimaki-pi-install.sh
fi
