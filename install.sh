#!/bin/bash
# install.sh — blank-Arch → working Nirimaki, top-level entrypoint.
#
# Quickstart (clone-yourself flow):
#
#   git clone https://github.com/kingkill85/nirimaki.git \
#       ~/.local/share/nirimaki
#   bash ~/.local/share/nirimaki/install.sh
#
# What this does — at a glance:
#
#   pre-flight   →  packaging  →  config  →  shell-setup
#                                         →  theme-apply
#                                         →  login (keyring + SDDM)
#                                         →  plymouth (LUKS-aware)
#                                         →  verify
#                                         →  reboot-needed report
#
# Each step is a function defined in install/<step>.sh. The full
# session is captured to /var/log/nirimaki-install.log via `script
# -qefc` so a failure can be diagnosed after the fact — same pattern
# bin/nirimaki-update already uses.
#
# Idempotency — first-run AND repair: every step tests before acting.
# Re-running `bash install.sh` after a partial failure or to refresh
# packages is safe.
#
# Spec — docs/install-steps.md is canonical for everything this
# script does. Handoff context — docs/install-sh-handoff.md.

set -e

# ---- 0. Log capture --------------------------------------------------
# Re-exec under `script -qefc` so progress bars (pacman/paru) keep
# redrawing (they detect a TTY) while the full session is captured
# for post-mortem. Mirrors bin/nirimaki-update.
#
# We log to /var/log/ rather than /tmp/ because /tmp is volatile and
# install issues often only surface after a reboot. /var/log/ needs
# root once for the create+chmod, then the user owns the file.
LOG_FILE="/var/log/nirimaki-install.log"

if [[ -z ${NIRIMAKI_INSTALL_LOGGED:-} ]]; then
  if [[ ! -w "$(dirname "$LOG_FILE")" ]] && command -v sudo >/dev/null 2>&1; then
    # Touch the file as root so `script` can append; chown to user so
    # subsequent writes don't need sudo on every step.
    sudo touch "$LOG_FILE"
    sudo chown "$USER:$USER" "$LOG_FILE"
    sudo chmod 600 "$LOG_FILE"
  fi
  cmd=$(printf '%q ' "$0" "$@")
  exec env NIRIMAKI_INSTALL_LOGGED=1 script -qefc "$cmd" "$LOG_FILE"
fi

# ---- 1. Resolve repo root + source helpers --------------------------
# install.sh always sits at the repo root, install/*.sh one level down.
# helpers.sh exports REPO_DIR using the same logic; we just re-derive
# it here so the first lines of output have it before helpers loads.
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/install" && pwd)"
# shellcheck source=install/helpers.sh
source "$INSTALL_DIR/helpers.sh"

# Reboot bookkeeping — set by step scripts, read by the trailer.
NIRIMAKI_NEEDS_REBOOT=0
NIRIMAKI_REBOOT_REASON=()
NIRIMAKI_NEEDS_RELOG=0
export NIRIMAKI_NEEDS_REBOOT NIRIMAKI_REBOOT_REASON NIRIMAKI_NEEDS_RELOG

trap 'rc=$?; echo; printf "\033[31m✗ Install failed (exit %d).\nFull log: %s\033[0m\n" "$rc" "$LOG_FILE" >&2' ERR

# ---- 2. Banner -------------------------------------------------------
cat <<'EOF'

  _   _ _      _                _    _
 | \ | (_)_ __(_)_ __ ___   __ _| | _(_)
 |  \| | | '__| | '_ ` _ \ / _` | |/ / |
 | |\  | | |  | | | | | | | (_| |   <| |
 |_| \_|_|_|  |_|_| |_| |_|\__,_|_|\_\_|

 Omarchy-style desktop for Arch Linux on niri + Quickshell.

EOF

echo "Log: $LOG_FILE"
echo

# ---- 3. Pre-flight + sudo prime -------------------------------------
# preflight may re-set REPO_DIR if it ends up cloning the repo into
# place. Source it before the rest so the new value propagates.
# shellcheck source=install/preflight.sh
source "$INSTALL_DIR/preflight.sh"
preflight

# Re-point INSTALL_DIR at REPO_DIR/install in case preflight cloned
# a fresh copy to ~/.local/share/nirimaki/ and we started from
# somewhere else.
INSTALL_DIR="$REPO_DIR/install"

sudo_prime

# ---- 4. The work ----------------------------------------------------
# shellcheck source=install/packaging.sh
source "$INSTALL_DIR/packaging.sh"
packaging

# shellcheck source=install/config.sh
source "$INSTALL_DIR/config.sh"
configure

# shellcheck source=install/shell-setup.sh
source "$INSTALL_DIR/shell-setup.sh"
shell_setup

# shellcheck source=install/theme-apply.sh
source "$INSTALL_DIR/theme-apply.sh"
theme_apply

# shellcheck source=install/login.sh
source "$INSTALL_DIR/login.sh"
login_setup

# shellcheck source=install/plymouth.sh
# Runs last so a misparse or mkinitcpio failure doesn't cascade into
# the rest of the install.
source "$INSTALL_DIR/plymouth.sh"
plymouth_setup

# shellcheck source=install/verify.sh
source "$INSTALL_DIR/verify.sh"
verify

# ---- 5. Stop the sudo heartbeat -------------------------------------
if [[ -n ${NIRIMAKI_SUDO_HEARTBEAT_PID:-} ]]; then
  kill "$NIRIMAKI_SUDO_HEARTBEAT_PID" 2>/dev/null || true
fi

# ---- 6. Reboot / re-login summary -----------------------------------
section "Install complete"
echo
echo "  Log:  $LOG_FILE"
echo

if (( NIRIMAKI_NEEDS_REBOOT )); then
  reason="$(IFS=' + '; echo "${NIRIMAKI_REBOOT_REASON[*]}")"
  echo "  A REBOOT is recommended:  $reason"
  echo
  read -r -p "  Reboot now? [y/N] " ans
  case "${ans,,}" in
    y|yes)
      systemctl reboot
      exit 0
      ;;
  esac
fi

if (( NIRIMAKI_NEEDS_RELOG )); then
  echo "  Log out + back in to pick up your new login shell (fish)."
  echo
fi

echo "  Next steps:"
echo "    • Log into SDDM (or reboot) to start your first niri session."
echo "    • Open the menu (Mod+Space → Settings) to explore themes / webapps / dev envs."
echo
