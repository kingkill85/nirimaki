function cx --description 'Claude Code (clears screen, bypass permissions)'
    # Same shape as Omarchy's `cx` alias — clears scrollback and runs
    # claude with bypass permissions for long IDE-style sessions.
    printf '\033[2J\033[3J\033[H'
    command claude --permission-mode bypassPermissions $argv
end
