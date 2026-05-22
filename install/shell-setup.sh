#!/bin/bash
# install/shell-setup.sh — bootstrap fisher + LazyVim + tldr.
#
# Implements docs/install-steps.md §7 + §8 + §9.
#
# §7 — fisher bootstrap, then `fisher update` reads ~/.config/fish/
#      fish_plugins (seeded by config.sh) and pulls every listed plugin.
# §8 — LazyVim headless sync. lazy-lock.json is gitignored so each
#      user gets fresh plugins.
# §9 — `tldr --update`. One-time ~2 MB cache download.
#
# This file is sourced; shell_setup() is the entrypoint.

if [[ -n ${NIRIMAKI_SHELL_SETUP_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_SHELL_SETUP_LOADED=1

# §7 — fisher bootstrap.
#
# Spec snippet runs the install in a single `fish -c` invocation;
# we follow that pattern. If fisher's installer ever changes its
# canonical URL we'll need to update this block.
_sh_fisher() {
  section "Shell: fisher bootstrap + plugin install (§7)"
  if ! command -v fish >/dev/null 2>&1; then
    warn "fish not installed — skipping fisher bootstrap"
    return 0
  fi
  fish -c '
    if not functions -q fisher
      curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    end
    fisher update
  ' || warn "fisher bootstrap had a non-zero exit — review log."
  ok "fisher + plugins installed"
}

# §8 — LazyVim headless sync. Quiet timeout so a hung mirror doesn't
# wedge install.sh forever.
_sh_lazyvim() {
  section "Shell: LazyVim headless plugin sync (§8)"
  if ! command -v nvim >/dev/null 2>&1; then
    warn "nvim not installed — skipping LazyVim sync"
    return 0
  fi
  if ! timeout 600 nvim --headless "+Lazy! sync" +qa 2>/dev/null; then
    warn "LazyVim sync exited non-zero (or timed out) — run 'nvim +Lazy sync' after install"
  else
    ok "LazyVim plugins synced"
  fi
}

# §9 — tldr offline cache. Tealdeer's `--update`, ~2 MB.
_sh_tldr() {
  section "Shell: tldr offline cache (§9)"
  if ! command -v tldr >/dev/null 2>&1; then
    warn "tldr not installed — skipping cache update"
    return 0
  fi
  tldr --update || warn "tldr --update non-zero — retry later with 'tldr --update'"
  ok "tldr cache populated"
}

shell_setup() {
  _sh_fisher
  _sh_lazyvim
  _sh_tldr
}
