# abbreviations.fish — fish abbr set for Nirimaki.
#
# Abbreviations > aliases: they expand visibly when you press space,
# so the running command stays discoverable. Lands in H1 as a small
# baseline; tools added in later steps extend this file (eza, lazygit,
# tldr, etc).

# Guard: only re-define when interactive. (Abbreviations don't apply
# to scripts but `abbr` still records them; the guard keeps `fish -c`
# fast.)
if not status is-interactive
    exit
end

# --- core navigation ---------------------------------------------------
abbr -a ..   'cd ..'
abbr -a ...  'cd ../..'
abbr -a .... 'cd ../../..'

# --- shell hygiene -----------------------------------------------------
abbr -a c   clear
abbr -a q   exit
abbr -a x   exit

# --- git ---------------------------------------------------------------
abbr -a g    git
abbr -a gs   'git status'
abbr -a ga   'git add'
abbr -a gc   'git commit'
abbr -a gca  'git commit --amend'
abbr -a gp   'git push'
abbr -a gpl  'git pull'
abbr -a gl   'git log --oneline --graph --decorate'
abbr -a gd   'git diff'
abbr -a gds  'git diff --staged'
abbr -a gco  'git checkout'
abbr -a gb   'git branch'
abbr -a gsw  'git switch'

# --- systemd (user) ----------------------------------------------------
abbr -a sc   'systemctl --user'
abbr -a jc   'journalctl --user -e'

# --- Nirimaki helpers --------------------------------------------------
abbr -a tl   'qs-theme-list'
abbr -a ts   'qs-theme-set'

# --- eza (modern ls) ---------------------------------------------------
# `ls` itself stays as fish's stock ls in scripts (abbr only fires when
# typed interactively + followed by space). Interactive ls gets icons,
# git column, sane time format.
if command -q eza
    abbr -a ls 'eza --icons --git --group-directories-first'
    abbr -a ll 'eza -l --icons --git --group-directories-first --time-style=long-iso'
    abbr -a la 'eza -la --icons --git --group-directories-first --time-style=long-iso'
    abbr -a lt 'eza --tree --icons --level=2 --group-directories-first'
    abbr -a lT 'eza --tree --icons --level=4 --group-directories-first'
end

# --- bat (modern cat) --------------------------------------------------
# `cat` stays plain so pipes / redirects don't get bat's decorations
# silently. Use `b` / `bp` explicitly when you want syntax highlighting.
if command -q bat
    abbr -a b   'bat'
    abbr -a bp  'bat --plain'        # no line numbers, just colour
    abbr -a bn  'bat --style=numbers' # line numbers, no git gutter
end

# --- ripgrep / fd ------------------------------------------------------
# Short aliases for the common "search this dir" cases.
if command -q rg
    abbr -a rgi 'rg --ignore-case'
    abbr -a rgh 'rg --hidden'        # include dotfiles
end
if command -q fd
    abbr -a fdh 'fd --hidden'
end

# --- zoxide ------------------------------------------------------------
# `cd` is replaced by zoxide via `--cmd cd` (see conf.d/tools.fish).
# Literal paths still win first; `cd nirim` from anywhere jumps into
# the most-recent nirimaki dir.

# --- lazygit / tldr / yazi / misc Tier-2 ------------------------------
if command -q lazygit
    abbr -a lg lazygit
end
if command -q tldr
    abbr -a help tldr      # `help tar` is faster than `man tar` for the 90%
end
if command -q yazi
    abbr -a y yazi         # one-key file manager
end
