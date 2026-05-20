function tsl --description 'Tmux Swarm Layout — N panes all running the same command'
    # Ported from basecamp/omarchy@default/bash/fns/tmux. Tiles N panes
    # in the current window, each running the same command. Useful for
    # parallel AI agents, log tails, watches, etc.
    #
    # Usage: tsl <pane_count> <command>
    #   tsl 4 claude
    #   tsl 6 'watch -n2 free -h'

    if test -z "$argv[1]"; or test -z "$argv[2]"
        echo "Usage: tsl <pane_count> <command>" >&2
        return 1
    end
    if test -z "$TMUX"
        echo "tsl: must be inside a tmux session" >&2
        return 1
    end

    set -l count $argv[1]
    set -l cmd $argv[2]
    set -l current_dir $PWD
    set -l panes $TMUX_PANE

    tmux rename-window -t $TMUX_PANE (basename $current_dir)

    while test (count $panes) -lt $count
        set -l last_pane $panes[-1]
        set -l new_pane (tmux split-window -h -t $last_pane -c $current_dir -P -F '#{pane_id}')
        set panes $panes $new_pane
        tmux select-layout -t $panes[1] tiled
    end

    for pane in $panes
        tmux send-keys -t $pane "$cmd" C-m
    end

    tmux select-pane -t $panes[1]
end
