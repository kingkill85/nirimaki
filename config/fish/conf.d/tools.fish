# tools.fish — initialise the Phase H3 core tools.
#
# Each `command -q <tool>` guard keeps fish booting cleanly even if a
# tool is missing (fresh install, partial setup, etc.).

if not status is-interactive
    exit
end

# --- zoxide -----------------------------------------------------------
# `--cmd cd` makes zoxide REPLACE the built-in cd. Literal paths still
# work first (cd /tmp, cd .., cd ./subdir) — zoxide only falls back to
# frecency match when no literal path resolves. So this is purely
# additive: every cd you know still works, plus `cd nirim` jumps into
# the most-recent nirimaki dir from anywhere.
#
# Provides:
#   cd <pat>   smart cd — literal first, frecency fallback
#   cdi        interactive fzf picker over the database
if command -q zoxide
    zoxide init fish --cmd cd | source
end

# --- fzf --------------------------------------------------------------
# Plain `fzf --fish | source` would wire the stock bindings — but the
# fzf.fish plugin (installed via fisher in H5) provides RICHER pickers
# with previews and git integration on the same keys + extra bindings:
#   Ctrl-R          history with preview
#   Ctrl-Alt-F      directory search
#   Ctrl-Alt-S      git status (multi-select stage)
#   Ctrl-Alt-L      git log
#   Ctrl-Alt-P      processes
#   Ctrl-V          shell variables
# fzf.fish's conf.d/fzf.fish loads automatically; nothing to do here.

# --- pagers / editor --------------------------------------------------
# bat as the help pager so `--help` output gets syntax-highlighted
# paging. MANPAGER uses bat's `man` lexer for colourised man pages.
if command -q bat
    set -gx PAGER bat
    set -gx MANPAGER 'sh -c "col -bx | bat -l man -p"'
    set -gx MANROFFOPT '-c'
    set -gx BAT_THEME nirimaki  # custom theme rendered by qs-theme-set per Nirimaki theme
end

# Default editor for git, sudoedit, eff, tdl, ...  LazyVim is wired in
# H/LazyVim, so plain `nvim` lands in a themed IDE.
if command -q nvim
    set -gx EDITOR nvim
    set -gx VISUAL nvim
end

# --- pay-respects -----------------------------------------------------
# Maintained Rust rewrite of `thefuck`. Defines an `f` function that
# rewrites the previous failed command into a corrected one.
if command -q pay-respects
    pay-respects fish --alias | source
end

# --- bookmarks (bm function) ------------------------------------------
# Ctrl-B  fzf picker over saved bookmarks → cd into the chosen one.
# `bm` itself is defined in functions/bm.fish; this just wires the key.
bind ctrl-b 'bm; commandline -f repaint'
if bind -M insert >/dev/null 2>&1
    bind -M insert ctrl-b 'bm; commandline -f repaint'
end

# --- theme colors -----------------------------------------------------
# fish_color_* universals are set live by qs-theme-set when a theme is
# swapped (so all running shells re-tint instantly). This safety-net
# source runs on fresh sessions in case the universal vars were never
# initialised (clean install, wiped ~/.local/share/fish/, etc).
if test -f ~/.config/theme/current/fish-colors.fish
    source ~/.config/theme/current/fish-colors.fish
end
