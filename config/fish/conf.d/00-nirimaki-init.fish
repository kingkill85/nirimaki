# 00-nirimaki-init.fish — early init for Nirimaki.
#
# Sourced first via the `00-` prefix (fish loads conf.d/* in
# alphabetical order). Sets up PATH and starship before any other
# nirimaki conf.d file runs. The user's own ~/.config/fish/config.fish
# loads AFTER all conf.d files, so user edits always win.

# Non-interactive (scripts, subshells used by tools): bail early so we
# don't slow down every `fish -c '...'` call. Interactive-only setup
# goes below the guard.
if not status is-interactive
    exit
end

# ~/.local/bin holds the nirimaki-* helpers (linked by dev-link.sh). Add
# it to PATH if it isn't already — Arch's default fish path does not
# include it.
if test -d "$HOME/.local/bin"
    if not contains "$HOME/.local/bin" $PATH
        set -gx PATH "$HOME/.local/bin" $PATH
    end
end

# Starship prompt. Guard so a starship-less install boots cleanly.
if command -q starship
    starship init fish | source
end

# mise — version manager for the Install → Development menu's dev envs
# (ruby/node/go/python/dotnet/…). `mise activate` prepends its shim
# dir to PATH so the installed tools resolve. Guarded so a mise-less
# install boots cleanly.
if command -q mise
    mise activate fish | source
end
