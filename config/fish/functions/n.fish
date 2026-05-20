function n --description 'nvim — opens current dir if no args'
    # Ported from Omarchy's bash:
    #   n() { if [ "$#" -eq 0 ]; then command nvim . ; else command nvim "$@"; fi; }
    if test (count $argv) -eq 0
        command nvim .
    else
        command nvim $argv
    end
end
