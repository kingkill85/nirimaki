# config.fish — fish entry point for Nirimaki.
#
# Per-feature config lives in conf.d/ (fish auto-sources every *.fish
# there). This file only handles things that need to happen ONCE at
# shell start, and only for interactive sessions.

# Non-interactive (scripts, subshells used by tools): bail early so we
# don't slow down every `fish -c '...'` call. Interactive-only setup
# goes below the guard.
if not status is-interactive
    exit
end

# ~/.local/bin holds the qs-* helpers (linked by dev-link.sh). Add it
# to PATH if it isn't already — Arch's default fish path does not
# include it.
if test -d "$HOME/.local/bin"
    if not contains "$HOME/.local/bin" $PATH
        set -gx PATH "$HOME/.local/bin" $PATH
    end
end

# Starship prompt. Installed in H2; guard so H1 fish boots cleanly.
if command -q starship
    starship init fish | source
end
