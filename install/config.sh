#!/bin/bash
# install/config.sh — wire the repo into the user's live config.
#
# Implements docs/install-steps.md §3 + §4 + §5 + §6.
#
# §3 — fish as the login shell.
# §4 — config copy + symlink contract. Mirrors dev-link.sh's two
#      flavours: dir-symlink for repo-owned content (Quickshell,
#      nvim, theme templates/themes), seed-once-copy for user-owned
#      files (niri *.kdl, foot.ini, tmux.conf, config.fish).
# §5 — ~/.bashrc prepend: source the upgrade-tracked default/bash/rc
#      iff the marker line isn't already there.
# §6 — ~/.gitconfig delta block (idempotent append).
#
# This file is sourced; configure() is the entrypoint.

if [[ -n ${NIRIMAKI_CONFIG_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_CONFIG_LOADED=1

# §3 — fish as the login shell.
_cfg_shell() {
  section "Configure: fish as login shell"
  if ! grep -qx /usr/bin/fish /etc/shells; then
    echo /usr/bin/fish | sudo tee -a /etc/shells >/dev/null
    ok "added /usr/bin/fish to /etc/shells"
  else
    ok "/usr/bin/fish already in /etc/shells"
  fi
  local current_shell
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ $current_shell == "/usr/bin/fish" ]]; then
    ok "login shell already fish"
  else
    info "switching login shell to fish (will take effect on next login)"
    # chsh (setuid) prompts for the user's password via PAM even when
    # called by the user themselves — our passwordless sudo doesn't
    # cover it. Route through sudo instead so the install stays silent.
    sudo chsh -s /usr/bin/fish "$USER" \
      || warn "chsh failed — run 'sudo chsh -s /usr/bin/fish $USER' manually after install"
    NIRIMAKI_NEEDS_RELOG=1
  fi
}

# §4 — config copy + symlink contract.
#
# Two helpers from helpers.sh: seed_user_file (copy-once) and a
# light symlink helper inline below. We don't shell out to dev-link.sh
# because dev-link.sh's REPO_DIR detection points at the dev repo,
# not the canonical ~/.local/share/nirimaki/ end-user clone.
#
# `link_dir` — point $dest at $src; if $dest already correct, no-op;
# if $dest is a wrong symlink, replace; if $dest is a real dir/file,
# back up to <dest>.pre-install and link.
_link_dir() {
  local src="$1" dest="$2"
  if [[ -L $dest ]]; then
    local target
    target="$(readlink "$dest")"
    if [[ $target == "$src" ]]; then
      ok "link ok $dest"
      return 0
    fi
    rm "$dest"
  elif [[ -e $dest ]]; then
    local backup="$dest.pre-install"
    if [[ -e $backup ]]; then
      backup="$backup.$(date +%s)"
    fi
    mv "$dest" "$backup"
    warn "moved existing $dest → $backup"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  ok "link $dest -> $src"
}

# Per-file link variant, used for ~/.local/bin/nirimaki-* and the
# per-file samples under ~/.config/nirimaki/.
_link_file() {
  local src="$1" dest="$2"
  if [[ -L $dest && "$(readlink "$dest")" == "$src" ]]; then
    return 0
  fi
  if [[ -L $dest || -e $dest ]]; then
    rm -f "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
}

_cfg_links() {
  section "Configure: seed + symlink"

  # The repo lives at $REPO_DIR — which on end-user installs is
  # already ~/.local/share/nirimaki. Make sure default/ and bin/ are
  # reachable at the canonical paths the rest of the system expects.
  # (~/.local/share/nirimaki/default/ is what user-side ~/.config/niri/
  # config.kdl `include`s; ~/.local/share/nirimaki/bin/ is referenced
  # in default/niri/bindings.kdl.)
  if [[ "$REPO_DIR" != "$HOME/.local/share/nirimaki" ]]; then
    _link_dir "$REPO_DIR/default"         "$HOME/.local/share/nirimaki/default"
    _link_dir "$REPO_DIR/bin"             "$HOME/.local/share/nirimaki/bin"
    _link_dir "$REPO_DIR/plugins/builtin" "$HOME/.local/share/nirimaki/plugins/builtin"
  else
    ok "repo at canonical path — no default/ + bin/ + plugins/ symlinks needed"
  fi

  # Pure repo-owned dirs: dir-symlink.
  _link_dir "$REPO_DIR/config/quickshell"      "$HOME/.config/quickshell"
  _link_dir "$REPO_DIR/config/nvim"            "$HOME/.config/nvim"
  mkdir -p "$HOME/.config/theme"
  _link_dir "$REPO_DIR/config/theme/templates" "$HOME/.config/theme/templates"
  _link_dir "$REPO_DIR/config/theme/themes"    "$HOME/.config/theme/themes"

  # niri user files: copy-once, never overwritten.
  mkdir -p "$HOME/.config/niri"
  for seed in "$REPO_DIR"/config/niri/*.kdl; do
    seed_user_file "$seed" "$HOME/.config/niri/$(basename "$seed")"
  done

  # foot.ini: whole-file user-owned. Theme tracking via the
  # `include=~/.config/theme/current/foot.ini` line inside.
  mkdir -p "$HOME/.config/foot"
  seed_user_file "$REPO_DIR/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"

  # tmux.conf: whole-file user-owned (Omarchy convention).
  mkdir -p "$HOME/.config/tmux"
  seed_user_file "$REPO_DIR/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"

  # fish: config.fish + fish_plugins are OVERWRITTEN unconditionally on
  # every install.sh run. Some distros (CachyOS, ...) pre-seed their own
  # ~/.config/fish/config.fish with the user's home as part of the
  # base install — seed-once would let that distro default win and our
  # config never lands. On vanilla Arch neither file exists yet, so
  # cp -f just creates them. Users who customise post-install own those
  # edits at their own risk; install.sh is meant for fresh boxes.
  # conf.d/ completions/ functions/ themes/ are repo-owned symlinks
  # (_link_dir already backs up existing dirs to .pre-install).
  mkdir -p "$HOME/.config/fish"
  cp -f "$REPO_DIR/config/fish/config.fish"  "$HOME/.config/fish/config.fish"
  cp -f "$REPO_DIR/config/fish/fish_plugins" "$HOME/.config/fish/fish_plugins"
  ok "wrote ~/.config/fish/{config.fish,fish_plugins}"
  for fish_dir in conf.d completions functions themes; do
    [[ -d "$REPO_DIR/config/fish/$fish_dir" ]] || continue
    _link_dir "$REPO_DIR/config/fish/$fish_dir" "$HOME/.config/fish/$fish_dir"
  done

  # nirimaki-* helpers: per-file symlinks into ~/.local/bin so the
  # PATH order stays predictable.
  mkdir -p "$HOME/.local/bin"
  shopt -s nullglob
  for tool in "$REPO_DIR"/bin/nirimaki*; do
    [[ -f $tool ]] || continue
    chmod +x "$tool"
    _link_file "$tool" "$HOME/.local/bin/$(basename "$tool")"
  done
  shopt -u nullglob
  ok "linked nirimaki-* helpers into ~/.local/bin"

  # User-owned plugin overrides file: seeded once with a comment
  # shell.json — the user's positional bar layout + inline per-widget
  # settings (Phase N / Group C of the Quickshell migration). The
  # nirimaki-config-migrate script is idempotent: on a fresh install it
  # computes shell.json from the plugin manifests; on a re-run / upgrade
  # it converts an existing plugins.json forward; once shell.json
  # exists it exits without touching anything.
  mkdir -p "$HOME/.config/nirimaki"
  if [[ -x $REPO_DIR/bin/nirimaki-config-migrate ]]; then
    "$REPO_DIR/bin/nirimaki-config-migrate" >/dev/null 2>&1 || true
    if [[ -e "$HOME/.config/nirimaki/shell.json" ]]; then
      ok "seeded ~/.config/nirimaki/shell.json"
    else
      info "nirimaki-config-migrate did not write shell.json — the legacy fallback in Plugins.qml keeps the bar working until next run"
    fi
  fi

  # ~/.config/nirimaki/ samples — per-file symlinks so user-added
  # active hooks coexist in the same dirs.
  local sample rel dest
  shopt -s globstar nullglob
  for sample in "$REPO_DIR"/config/nirimaki/**/*; do
    [[ -f $sample ]] || continue
    rel="${sample#$REPO_DIR/config/nirimaki/}"
    dest="$HOME/.config/nirimaki/$rel"
    _link_file "$sample" "$dest"
  done
  shopt -u globstar nullglob
  ok "linked ~/.config/nirimaki/ samples"

  # .desktop launchers — per-file, sit alongside user-installed
  # webapp .desktops in ~/.local/share/applications/.
  if [[ -d $REPO_DIR/config/applications ]]; then
    mkdir -p "$HOME/.local/share/applications"
    shopt -s nullglob
    for d in "$REPO_DIR"/config/applications/*.desktop; do
      _link_file "$d" "$HOME/.local/share/applications/$(basename "$d")"
    done
    shopt -u nullglob
    ok "linked config/applications/*.desktop"
  fi
}

# §5 — prepend the source-line block to ~/.bashrc.
#
# Marker chosen so future install.sh runs detect the block and skip.
# Anything the user adds BELOW this block keeps winning (bash sources
# top-to-bottom).
_cfg_bashrc() {
  section "Configure: ~/.bashrc — load default/bash/rc"
  local rc="$HOME/.bashrc"
  local marker="# Nirimaki — load shared bash defaults"
  if [[ -f $rc ]] && grep -qF "$marker" "$rc"; then
    ok "Nirimaki block already present in $rc"
    return 0
  fi
  # Prepend (matching the spec — the source line must come before any
  # user content so user-content wins via evaluation order).
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
# Nirimaki — load shared bash defaults (starship, mise, $EDITOR).
# This must stay near the top so anything below in your ~/.bashrc
# runs AFTER and wins via bash's evaluation order.
[[ -f $HOME/.local/share/nirimaki/default/bash/rc ]] && \
  source "$HOME/.local/share/nirimaki/default/bash/rc"

EOF
  [[ -f $rc ]] && cat "$rc" >> "$tmp"
  mv "$tmp" "$rc"
  ok "prepended Nirimaki block to $rc"
}

# §6 — ~/.gitconfig delta + niceties. Idempotent: only writes blocks
# that aren't already there.
_cfg_gitconfig() {
  section "Configure: ~/.gitconfig delta block"
  local gc="$HOME/.gitconfig"
  if [[ -f $gc ]] && grep -qE '^\[delta\]' "$gc"; then
    ok "delta block already in $gc"
    return 0
  fi
  # Tabs as in the spec.
  cat >> "$gc" <<'EOF'

[core]
	pager = delta
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	line-numbers = true
	side-by-side = true
	syntax-theme = ansi
[merge]
	conflictstyle = zdiff3
EOF
  ok "appended delta block to $gc"
}

configure() {
  _cfg_shell
  _cfg_links
  _cfg_bashrc
  _cfg_gitconfig
}
