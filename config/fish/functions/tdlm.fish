function tdlm --description 'Multi-window tdl — one window per subdirectory'
    # Ported from basecamp/omarchy@default/bash/fns/tmux. From the
    # current directory, opens one tmux window per immediate
    # subdirectory and runs `tdl <ai>` inside each.
    #
    # Usage: tdlm <ai_cmd> [<second_ai_cmd>]

    if test -z "$argv[1]"
        echo "Usage: tdlm <ai_cmd> [<second_ai_cmd>]" >&2
        return 1
    end
    if test -z "$TMUX"
        echo "tdlm: must be inside a tmux session" >&2
        return 1
    end

    set -l ai $argv[1]
    set -l ai2 $argv[2]
    set -l base_dir $PWD

    # Rename the session after this dir (tmux disallows . and :).
    set -l session_name (basename $base_dir | tr '.:' '--')
    tmux rename-session $session_name

    set -l first true
    for dir in $base_dir/*/
        test -d $dir; or continue
        set -l dirpath (string trim -r --chars=/ -- $dir)

        if test "$first" = true
            tmux send-keys -t $TMUX_PANE "cd '$dirpath' && tdl $ai $ai2" C-m
            set first false
        else
            set -l pane_id (tmux new-window -c $dirpath -P -F '#{pane_id}')
            tmux send-keys -t $pane_id "tdl $ai $ai2" C-m
        end
    end
end
