function tdl --description 'Tmux Dev Layout — editor + AI pane + terminal'
    # Ported from basecamp/omarchy@default/bash/fns/tmux. Splits the
    # current tmux window into:
    #   left 70% top    → $EDITOR
    #   right 30%       → first AI command (e.g. `claude`, `codex`, `cx`)
    #   right 30% bottom (optional) → second AI command
    #   bottom 15%      → empty shell pane (terminal)
    #
    # Usage: tdl <ai_cmd> [<second_ai_cmd>]
    #   tdl claude
    #   tdl claude codex

    if test -z "$argv[1]"
        echo "Usage: tdl <ai_cmd> [<second_ai_cmd>]" >&2
        return 1
    end
    if test -z "$TMUX"
        echo "tdl: must be inside a tmux session" >&2
        return 1
    end

    set -l current_dir $PWD
    set -l ai $argv[1]
    set -l ai2 $argv[2]
    set -l editor_pane $TMUX_PANE

    tmux rename-window -t $editor_pane (basename $current_dir)

    # Bottom terminal — 15% of editor pane height.
    tmux split-window -v -p 15 -t $editor_pane -c $current_dir

    # Right AI pane — 30% of editor pane width.
    set -l ai_pane (tmux split-window -h -p 30 -t $editor_pane -c $current_dir -P -F '#{pane_id}')

    if test -n "$ai2"
        set -l ai2_pane (tmux split-window -v -t $ai_pane -c $current_dir -P -F '#{pane_id}')
        tmux send-keys -t $ai2_pane "$ai2" C-m
    end

    tmux send-keys -t $ai_pane "$ai" C-m

    set -l editor $EDITOR
    test -z "$editor"; and set editor nvim
    tmux send-keys -t $editor_pane "$editor ." C-m

    tmux select-pane -t $editor_pane
end
