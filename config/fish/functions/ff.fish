function ff --description 'fzf file picker with preview (bat + kitty icat for images)'
    # Ported from Omarchy's bash. Preview command runs in the shell fzf
    # spawns for previews (bash), so the ${FZF_PREVIEW_COLUMNS} bash
    # expansions stay literal in this fish single-quoted string.
    set -l preview
    if test "$TERM" = xterm-kitty
        set preview 'case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'
    else
        set preview 'bat --style=numbers --color=always {}'
    end
    fzf --preview $preview $argv
end
