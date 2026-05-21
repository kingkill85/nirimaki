function cc --description 'Claude Code (plain)'
    # NOTE: this shadows /usr/bin/cc (the C compiler). To run the actual
    # compiler, use `command cc <args>`. The bypass-permissions / clear-
    # screen variant is `cx`.
    command claude $argv
end
