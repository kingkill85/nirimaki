function cc --description 'Claude Code (clears screen, bypass permissions)'
    # Renamed from Omarchy's `cx`. NOTE: this shadows /usr/bin/cc (the C
    # compiler). To run the actual compiler, use `command cc <args>`.
    printf '\033[2J\033[3J\033[H'
    command claude --permission-mode bypassPermissions $argv
end
