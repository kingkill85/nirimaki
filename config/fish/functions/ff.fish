function ff --description 'fzf file picker with preview (bat + sixel images in foot)'
    # Ported from Omarchy's bash. Preview command runs in the shell fzf
    # spawns for previews (bash), so the ${FZF_PREVIEW_COLUMNS} bash
    # expansions stay literal in this fish single-quoted string.
    #
    # Image preview path picks based on $TERM:
    #   foot* (default Nirimaki terminal) → img2sixel
    #   xterm-kitty                       → kitty icat (kept as fallback
    #                                       for when kitty is launched
    #                                       manually)
    #   anything else                     → bat-only, no image preview
    set -l preview
    if string match -q 'foot*' "$TERM"
        # Foot has native sixel support; img2sixel (libsixel) outputs
        # a sixel sequence that foot renders inline. Cell-size math is
        # approximate — foot reports terminal pixels via XTWINOPS but
        # fzf doesn't pass that through, so we cap on column count.
        set preview 'case $(file --mime-type -b {}) in image/*) img2sixel -w $((${FZF_PREVIEW_COLUMNS} * 8)) {} 2>/dev/null ;; *) bat --style=numbers --color=always {} ;; esac'
    else if test "$TERM" = xterm-kitty
        set preview 'case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'
    else
        set preview 'bat --style=numbers --color=always {}'
    end
    fzf --preview $preview $argv
end
