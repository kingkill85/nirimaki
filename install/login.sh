#!/bin/bash
# install/login.sh — login stack: gnome-keyring passwordless +
# Nirimaki SDDM theme.
#
# Implements docs/install-steps.md §13a + §13b.
#
# §13a — gnome-keyring auto-unlock. Wraps install/login/keyring.sh
#        which already exists and is idempotent.
# §13b — Nirimaki SDDM theme + state/ ownership + sddm.service
#        enable. Wraps install/login/sddm.sh.
#
# Important policy decision (user-set): we do NOT enable SDDM
# autologin from install.sh. The user explicitly said autologin
# should only ever be on with LUKS protecting the disk — and even
# then it's an opt-in, not a default. install/login/sddm.sh writes
# `[Theme] Current=nirimaki` to /etc/sddm.conf.d/10-nirimaki.conf
# but leaves any existing autologin.conf alone (additive).
#
# This file is sourced; login_setup() is the entrypoint.

if [[ -n ${NIRIMAKI_LOGIN_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_LOGIN_LOADED=1

_lg_keyring() {
  section "Login: gnome-keyring passwordless (§13a)"
  bash "$REPO_DIR/install/login/keyring.sh"
}

_lg_sddm_theme() {
  section "Login: SDDM theme + service enable (§13b)"
  bash "$REPO_DIR/install/login/sddm.sh"

  # Seed state/ with the active theme so the very first greeter
  # render isn't blank. nirimaki-sddm-sync reads from the active
  # ~/.config/theme/current/, so theme_apply() must have run before us.
  if command -v nirimaki-sddm-sync >/dev/null 2>&1; then
    nirimaki-sddm-sync || warn "nirimaki-sddm-sync exit non-zero — first greeter may be blank"
  else
    warn "nirimaki-sddm-sync not on PATH — state/ unseeded"
  fi

  info "enabling sddm.service"
  sudo systemctl enable sddm.service
  ok "sddm.service enabled"
}

login_setup() {
  _lg_keyring
  _lg_sddm_theme
}
