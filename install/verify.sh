#!/bin/bash
# install/verify.sh — sanity-check the result of install.sh.
#
# Implements docs/install-steps.md §14. Reports MISS lines without
# exiting non-zero — the install is "done" even if a verification
# step caught something missing, because most checks are best-effort
# (Quickshell IPC needs an active session, theme set needs a TTY-
# attached binary, etc.) and we'd rather surface them than fail the
# whole install.
#
# This file is sourced; verify() is the entrypoint.

if [[ -n ${NIRIMAKI_VERIFY_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_VERIFY_LOADED=1

_vr_shell() {
  local got
  got="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ $got == "/usr/bin/fish" ]]; then
    ok "login shell: fish"
  else
    warn "login shell: $got (expected /usr/bin/fish; will take effect after re-login)"
  fi
}

_vr_cli() {
  local missing=()
  for c in fish starship eza bat fzf zoxide rg fd delta lazygit tldr \
           pay-respects sd ouch dust duf procs xh hyperfine tokei \
           tmux yazi nvim jq mise opencode claude pi; do
    if command -v "$c" >/dev/null 2>&1; then
      ok "cli: $c"
    else
      warn "cli: MISS $c"
      missing+=("$c")
    fi
  done
  (( ${#missing[@]} == 0 )) && ok "all core CLI tools present"
}

_vr_niri() {
  if command -v niri >/dev/null 2>&1; then
    if niri validate -c "$HOME/.config/niri/config.kdl" >/dev/null 2>&1; then
      ok "niri config validates"
    else
      warn "niri validate failed — inspect ~/.config/niri/config.kdl"
    fi
  else
    warn "niri not installed"
  fi
}

_vr_quickshell_ipc() {
  # Won't work during install (no session yet). Best-effort.
  if command -v quickshell >/dev/null 2>&1; then
    if quickshell ipc call shell ping >/dev/null 2>&1; then
      ok "quickshell IPC alive"
    else
      warn "quickshell IPC not reachable (expected during install — verify after first niri login)"
    fi
  fi
}

_vr_theme_set() {
  # Don't actually flip themes during install — theme_apply.sh already
  # set tokyo-night. Just confirm the helper is wired.
  if command -v nirimaki-theme-set >/dev/null 2>&1; then
    ok "nirimaki-theme-set on PATH"
  else
    warn "nirimaki-theme-set NOT on PATH — config.sh may not have linked it"
  fi
}

_vr_feature_state() {
  local f="$HOME/.cache/nirimaki/state.json"
  if [[ -f $f ]]; then
    ok "feature-state cache present: $f"
  else
    warn "feature-state cache not yet populated (autostart writes it on first niri login)"
  fi
}

verify() {
  section "Verification (§14) — MISS lines are informational, not fatal"
  _vr_shell
  _vr_cli
  _vr_niri
  _vr_quickshell_ipc
  _vr_theme_set
  _vr_feature_state
}
