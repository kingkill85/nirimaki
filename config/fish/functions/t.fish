function t --description 'Attach to or create the "Work" tmux session'
    # Ported from Omarchy's `alias t='tmux attach || tmux new -s Work'`.
    # Single key to drop into a persistent named session — different
    # from the quake terminal (`Mod+grave`) which uses session `quake`.
    tmux attach; or tmux new -s Work
end
