function eff --description 'fzf file picker → open in $EDITOR'
    # Ported from Omarchy's `alias eff='$EDITOR "$(ff)"'`.
    set -l file (ff)
    test -z "$file"; and return 0
    set -l editor $EDITOR
    test -z "$editor"; and set editor nvim
    $editor $file
end
