#!/bin/bash
# install/theme-apply.sh — qt5ct/qt6ct seed + initial theme apply.
#
# Implements docs/install-steps.md §10 + §12.
#
# Why §12 runs FIRST (before §10's theme set): qt5ct.conf / qt6ct.conf
# carry the `color_scheme_path=` directive that nirimaki-theme-set
# leaves alone. If the file doesn't exist when theme-set runs, the
# Qt apps won't pick up the palette. So we seed the qt conf files
# first, then apply the theme.
#
# This file is sourced; theme_apply() is the entrypoint.

if [[ -n ${NIRIMAKI_THEME_APPLY_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_THEME_APPLY_LOADED=1

# §12 — qt5ct / qt6ct conf seed.
#
# qt5ct/qt6ct don't expand `~` or env vars in INI values, so we write
# the literal $HOME path. nirimaki-theme-set mutates only the
# `icon_theme=` line on each swap; the color_scheme_path= line stays
# the literal absolute path written here.
#
# Idempotent: if the file already contains a Nirimaki marker, leave
# it alone — the user may have customised `style=` or `icon_theme=`.
_th_qtct() {
  section "Theme: qt5ct + qt6ct config seed (§12)"
  local marker="# nirimaki-managed"
  for variant in qt5ct qt6ct; do
    local file="$HOME/.config/$variant/$variant.conf"
    if [[ -f $file ]] && grep -qF "$marker" "$file"; then
      ok "$file already nirimaki-managed (preserved)"
      continue
    fi
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
$marker — Appearance block is rewritten by install.sh.
[Appearance]
custom_palette=true
color_scheme_path=$HOME/.config/theme/current/qt-colors.conf
icon_theme=Yaru-blue
style=Fusion
EOF
    ok "wrote $file"
  done
}

# §10 — initial theme apply.
#
# `nirimaki theme set tokyo-night` renders every .tpl to its
# destination (kitty, btop, starship, lazygit, bat, yazi, fish, niri,
# qt, foot…), builds the bat cache, sources fish-colors, and IPCs
# Quickshell/niri/nvim sockets to hot-reload.
#
# On a fresh install Quickshell isn't running yet — the IPC call is
# harmless (theme-set tolerates a missing socket). The on-disk artefacts
# are what matter; first session start picks them up.
_th_apply() {
  section "Theme: initial apply — tokyo-night (§10)"
  local theme_set="$HOME/.local/bin/nirimaki-theme-set"
  if [[ ! -x $theme_set ]]; then
    warn "nirimaki-theme-set not on PATH yet — config.sh should have linked it. Skipping."
    return 0
  fi
  "$theme_set" tokyo-night || warn "initial theme set returned non-zero — re-run after first login"
  ok "active theme set to tokyo-night"
}

theme_apply() {
  _th_qtct
  _th_apply
}
