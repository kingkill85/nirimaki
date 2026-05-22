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
warn() { printf '%s\n' "${C_YEL}  !${C_RESET} $*" >&2; }
die()  { printf '%s\n' "${C_RED}  ✗${C_RESET} $*" >&2; exit 1; }

# `ok` is silent by default — too spammy with one line per file copied.
# Set NIRIMAKI_VERBOSE=1 to see them (useful for debugging install runs).
ok() {
  if [[ ${NIRIMAKI_VERBOSE:-0} == 1 ]]; then
    printf '%s\n' "${C_GRN}  ✓${C_RESET} $*" >&2
  fi
}

section() {
  printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET" >&2
}

# sudo_prime — ask once, keep alive for the rest of the run.
#
# Most install steps need root for pacman / systemctl / mkinitcpio.
# A 5-minute sudo timestamp + heartbeat isn't reliable: makepkg drops
# into separate sudo invocations, sub-shells lose the parent's $$
# matcher, and the timestamp's `tty_tickets` default makes pty
# differences (script wrapper, makepkg, …) prompt again. Result on a
# real run: 8+ password prompts.
#
# Omarchy's solution (mirrored here): write a temporary
# /etc/sudoers.d/99-nirimaki-installer that lets $USER run anything
# password-less, then remove it from the EXIT trap in install.sh.
# One prompt total — the initial `sudo -v` to write the rule.
#
# Risk: if install.sh is killed -9 / OOM-killed, the rule lingers.
# `nirimaki-update` could also clean it up later; for now we accept
# the (small) risk in exchange for a usable installer.
sudo_prime() {
  if [[ ${NIRIMAKI_SUDO_PRIMED:-0} == 1 ]]; then
    return 0
  fi
  info "Need sudo once — installer drops a passwordless rule for the rest of the run."
  sudo -v || die "sudo authentication failed."
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER" \
    | sudo install -m 440 /dev/stdin /etc/sudoers.d/99-nirimaki-installer \
    || die "failed to write sudoers rule"
  NIRIMAKI_SUDO_PRIMED=1
  export NIRIMAKI_SUDO_PRIMED
}

# sudo_cleanup — remove the temp sudoers rule. Idempotent; safe to
# call from an EXIT trap that might fire multiple times in pathological
# cases.
sudo_cleanup() {
  sudo rm -f /etc/sudoers.d/99-nirimaki-installer 2>/dev/null || true
}

# pacman_install <pkg> [pkg…] — idempotent. `--needed` skips
# already-installed packages, `--noconfirm` keeps the run hands-off.
# Output is captured to a log file and only printed on failure —
# otherwise the install.sh log is dominated by pacman's per-file
# install chatter. Set NIRIMAKI_VERBOSE=1 to stream pacman directly.
pacman_install() {
  (( $# > 0 )) || return 0
  info "pacman: $* (${#@} packages)"
  if [[ ${NIRIMAKI_VERBOSE:-0} == 1 ]]; then
    sudo pacman -S --needed --noconfirm "$@"
    return $?
  fi
  local log; log=$(mktemp)
  if sudo pacman -S --needed --noconfirm "$@" >"$log" 2>&1; then
    rm -f "$log"
  else
    local rc=$?
    echo >&2
    printf '%s---- pacman -S failed (exit %d) — last 40 lines: ----%s\n' "$C_RED" "$rc" "$C_RESET" >&2
    tail -40 "$log" >&2
    rm -f "$log"
    return "$rc"
  fi
}

# paru_install <pkg> [pkg…] — AUR variant. Same output redirection
# as pacman_install. paru's PKGBUILD-review prompts are bypassed by
# `--skipreview --noconfirm`.
paru_install() {
  (( $# > 0 )) || return 0
  command -v paru >/dev/null || die "paru not on PATH — bootstrap step skipped?"
  info "paru: $* (${#@} packages)"
  if [[ ${NIRIMAKI_VERBOSE:-0} == 1 ]]; then
    paru -S --needed --noconfirm --skipreview "$@"
    return $?
  fi
  local log; log=$(mktemp)
  if paru -S --needed --noconfirm --skipreview "$@" >"$log" 2>&1; then
    rm -f "$log"
  else
    local rc=$?
    echo >&2
    printf '%s---- paru -S failed (exit %d) — last 60 lines: ----%s\n' "$C_RED" "$rc" "$C_RESET" >&2
    tail -60 "$log" >&2
    rm -f "$log"
    return "$rc"
  fi
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
