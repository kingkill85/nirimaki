#!/bin/bash
# install/helpers.sh — shared utilities for the install scripts.
#
# Sourced by install.sh and every install/*.sh that follows. Keeps
# the formatting + sudo handling in one place so each step script
# can focus on its own work.
#
# Conventions:
#   - `info`/`warn`/`die` write to stderr so command output stays clean.
#   - `section` prints a divider so the captured log is easy to scan
#     after the fact (one block per per-phase script).
#   - `sudo_prime` is idempotent — repeated calls just refresh the
#     timestamp; the first call may prompt.
#   - `pacman_install`/`paru_install` batch their package list to
#     keep dependency resolution coherent and the run fast.
#
# This file is sourced, not executed — no shebang behaviour intended.

# Re-source guard: if a child script sources us a second time, just
# return — we don't want to redefine functions mid-run.
if [[ -n ${NIRIMAKI_HELPERS_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_HELPERS_LOADED=1

# Colours, but only when stderr is a TTY. Captured logs stay clean.
if [[ -t 2 ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_YEL=$'\033[33m'
  C_GRN=$'\033[32m'
  C_CYA=$'\033[36m'
else
  C_RESET= C_DIM= C_BOLD= C_RED= C_YEL= C_GRN= C_CYA=
fi

info() { printf '%s\n' "${C_CYA}==>${C_RESET} $*" >&2; }
ok()   { printf '%s\n' "${C_GRN}  ✓${C_RESET} $*" >&2; }
warn() { printf '%s\n' "${C_YEL}  !${C_RESET} $*" >&2; }
die()  { printf '%s\n' "${C_RED}  ✗${C_RESET} $*" >&2; exit 1; }

section() {
  printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET" >&2
}

# sudo_prime — ask once, keep alive for the rest of the run.
#
# Most install steps need root for pacman / systemctl / mkinitcpio.
# Prompting on each invocation makes the run feel laggy and breaks
# the `script -qefc` log capture. Instead: prime sudo at the start,
# then a background heartbeat refreshes the timestamp every 60s
# until install.sh exits.
sudo_prime() {
  if [[ ${NIRIMAKI_SUDO_PRIMED:-0} == 1 ]]; then
    return 0
  fi
  info "Priming sudo (you'll be asked once)…"
  sudo -v || die "sudo authentication failed."
  # Heartbeat — refreshes -v timestamp until parent shell exits.
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -nv 2>/dev/null || exit 0
      sleep 60
    done
  ) &
  NIRIMAKI_SUDO_HEARTBEAT_PID=$!
  export NIRIMAKI_SUDO_HEARTBEAT_PID
  NIRIMAKI_SUDO_PRIMED=1
  export NIRIMAKI_SUDO_PRIMED
}

# pacman_install <pkg> [pkg…] — idempotent. `--needed` means already-
# installed packages get skipped; `--noconfirm` keeps the run hands-off.
pacman_install() {
  (( $# > 0 )) || return 0
  info "pacman -S --needed: $*"
  sudo pacman -S --needed --noconfirm "$@"
}

# paru_install <pkg> [pkg…] — AUR variant. Requires paru on PATH
# (packaging.sh bootstraps it before calling us).
paru_install() {
  (( $# > 0 )) || return 0
  command -v paru >/dev/null || die "paru not on PATH — bootstrap step skipped?"
  info "paru -S --needed: $*"
  paru -S --needed --noconfirm "$@"
}

# read_pkglist <file> — yields one package name per line, ignoring
# blank lines and `#` comments. Used for install/base.packages.
read_pkglist() {
  local file="$1"
  [[ -f $file ]] || die "missing package list: $file"
  grep -v '^[[:space:]]*\(#\|$\)' "$file"
}

# need_cmd <cmd> [hint] — die with a hint if a tool is missing.
# Mostly used by preflight.sh.
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1${2:+ — $2}"
}

# ensure_line <file> <pattern> <line> — idempotent append.
# If <pattern> already matches a line in <file>, do nothing.
# Otherwise append <line> (creating <file> if missing).
# <file> is treated as a USER-OWNED dotfile — no sudo here.
ensure_line() {
  local file="$1" pattern="$2" line="$3"
  if [[ -f $file ]] && grep -qE -- "$pattern" "$file"; then
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$line" >> "$file"
}

# seed_user_file <src> <dest> — copy-once helper, matches dev-link.sh's
# seed_user_file semantics. If $dest already exists in any form (file,
# symlink, anything), leave it alone — the user owns it after the
# first install.
seed_user_file() {
  local src="$1" dest="$2"
  if [[ -e $dest || -L $dest ]]; then
    ok "keep $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  ok "seed $dest  <-  $src"
}

# REPO_DIR — absolute path of the repo, resolved from this file's
# location. install/helpers.sh always lives one directory below the
# repo root, so this is stable across both end-user (`~/.local/share/
# nirimaki/`) and dev (`~/Projekte/kingkill85/nirimaki/`) layouts.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_DIR
