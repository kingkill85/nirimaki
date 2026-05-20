function bm --description "Directory bookmarks (named pins)"
    # Storage: ~/.local/share/fish/bookmarks (per-machine state, not in repo).
    # Format: TAB-separated  name\tpath  — one per line.
    set -l file ~/.local/share/fish/bookmarks
    mkdir -p (path dirname $file)
    touch $file

    set -l cmd $argv[1]
    set -l rest $argv[2..-1]

    switch "$cmd"

        # No args → interactive fzf picker → cd into the chosen bookmark.
        case ""
            if not command -q fzf
                echo "bm: fzf required for interactive picker" >&2
                return 1
            end
            if not test -s $file
                echo "bm: no bookmarks yet — add one with `bm add <name>` (defaults to cwd)" >&2
                return 1
            end
            set -l picked (
                while read -l line
                    set -l parts (string split -m1 \t -- $line)
                    printf "%-20s %s\n" $parts[1] $parts[2]
                end <$file | fzf --reverse --height=40% --prompt='bookmarks › '
            )
            test -z "$picked"; and return 0
            # Re-extract the path by name (avoids width/padding fragility).
            set -l name (string trim (string sub --start=1 --length=20 -- $picked))
            set -l path (awk -F\t -v n="$name" '$1==n {print $2; exit}' $file)
            if test -z "$path"
                echo "bm: could not parse selection" >&2
                return 1
            end
            if not test -d $path
                echo "bm: path no longer exists: $path" >&2
                return 1
            end
            cd $path

        # Add a bookmark (defaults to cwd).  `bm add proj` / `bm add proj /some/dir`
        case add a
            set -l name $rest[1]
            set -l path $rest[2]
            if test -z "$name"
                echo "bm: usage: bm add <name> [path]" >&2
                return 1
            end
            test -z "$path"; and set path $PWD
            set -l abs (realpath -- $path 2>/dev/null)
            test -z "$abs"; and set abs $path
            set -l tmp (mktemp)
            awk -F\t -v n="$name" '$1!=n' $file >$tmp
            printf '%s\t%s\n' $name $abs >>$tmp
            mv $tmp $file
            echo "bm: $name → $abs"

        # Remove a bookmark by name.
        case rm r remove del
            set -l name $rest[1]
            if test -z "$name"
                echo "bm: usage: bm rm <name>" >&2
                return 1
            end
            set -l tmp (mktemp)
            awk -F\t -v n="$name" '$1!=n' $file >$tmp
            mv $tmp $file
            echo "bm: removed $name"

        # Jump directly: `bm go proj` (or `bm g proj`).
        case go g cd
            set -l name $rest[1]
            if test -z "$name"
                echo "bm: usage: bm go <name>" >&2
                return 1
            end
            set -l path (awk -F\t -v n="$name" '$1==n {print $2; exit}' $file)
            if test -z "$path"
                echo "bm: no bookmark named $name" >&2
                return 1
            end
            if not test -d $path
                echo "bm: path no longer exists: $path" >&2
                return 1
            end
            cd $path

        # List bookmarks as a table (no fzf).
        case ls list l
            if not test -s $file
                echo "bm: no bookmarks yet" >&2
                return 0
            end
            column -ts \t $file

        case '*'
            echo "bm: unknown subcommand: $cmd" >&2
            echo "    valid: add | rm | go | ls | (no arg → fzf picker)" >&2
            return 1
    end
end
