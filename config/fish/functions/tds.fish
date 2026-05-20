function tds --description 'Tmux Dev Square — editor / diff / terminal / opencode 4-pane'
    # Ported from basecamp/omarchy@default/bash/fns/tmux. Splits the
    # current tmux window into a 4-pane grid:
    #   top-left:    $EDITOR .
    #   top-right:   hunk diff --watch     (requires `hunk` cli)
    #   bottom-left: empty shell
    #   bottom-right: opencode             (requires `opencode` cli)
    #
    # Usage: tds   (no args)

    if test -n "$argv[1]"
        echo "Usage: tds" >&2
        return 1
    end
    if test -z "$TMUX"
        echo "tds: must be inside a tmux session" >&2
        return 1
    end

    set -l current_dir $PWD
    set -l editor_pane $TMUX_PANE

    tmux rename-window -t $editor_pane (basename $current_dir)

    set -l terminal_pane (tmux split-window -v -p 50 -t $editor_pane -c $current_dir -P -F '#{pane_id}')
    set -l diff_pane     (tmux split-window -h -p 50 -t $editor_pane -c $current_dir -P -F '#{pane_id}')
    set -l opencode_pane (tmux split-window -h -p 50 -t $terminal_pane -c $current_dir -P -F '#{pane_id}')

    set -l editor $EDITOR
    test -z "$editor"; and set editor nvim
    tmux send-keys -t $editor_pane "$editor ." C-m
    tmux send-keys -t $diff_pane     "hunk diff --watch" C-m
    tmux send-keys -t $opencode_pane "opencode" C-m

    tmux select-pane -t $editor_pane
end
