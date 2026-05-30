# starship.toml — Nirimaki themed prompt.
#
# Rendered by qs-theme-set from this template + the active theme's
# colors.toml. {{ key }} placeholders are substituted with hex colours
# (with leading `#`). Starship rereads this file on every prompt
# redraw, so a theme swap shows up on the next Enter — no signal
# needed.
#
# Layout: two lines.
#   line 1: [ssh host ·] cwd · git (branch/state/status) · project ctx
#           (package, docker, k8s) · runtime versions · cmd duration
#   line 2: exit status · jobs · prompt character — always at column 0
#           no matter how much state appeared above
#
# Design note: every segment past the directory/git core is CONTEXTUAL —
# Starship only renders a language/tool module when the cwd actually
# contains that ecosystem (or the state actually occurred). So a plain
# directory looks exactly like the minimal prompt; it only grows when a
# developer would want the extra signal.

add_newline = false

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_state\
$git_status\
$direnv\
$nix_shell\
$package\
$docker_context\
$nodejs\
$deno\
$bun\
$python\
$rust\
$golang\
$lua\
$java\
$kotlin\
$ruby\
$php\
$dotnet\
$zig\
$elixir\
$swift\
$haskell\
$c\
$kubernetes\
$cmd_duration\
$line_break\
$status\
$jobs\
$character\
"""

[character]
success_symbol = '[❯](bold {{ color2 }})'
error_symbol = '[❯](bold {{ color1 }})'
vimcmd_symbol = '[❮](bold {{ color4 }})'

# Last command's exit code — only renders on failure, so you see *why*
# the prompt char went red, not just that it did. pipestatus surfaces
# each stage of a failed pipeline.
[status]
disabled = false
pipestatus = true
pipestatus_separator = '[|]({{ color8 }})'
pipestatus_format = '[$pipestatus]({{ color1 }}) '
format = '[$symbol$status]($style) '
symbol = '✘ '
style = 'bold {{ color1 }}'

# Backgrounded jobs — only shows once there's at least one.
[jobs]
symbol = '✦ '
number_threshold = 1
symbol_threshold = 1
style = '{{ color3 }}'
format = '[$symbol$number]($style) '

# user@host only over SSH — local sessions stay clean.
[username]
show_always = false
style_user = 'bold {{ color1 }}'
style_root = 'bold {{ color1 }}'
format = '[$user]($style)'

[hostname]
ssh_only = true
style = 'bold {{ color5 }}'
format = '[@$hostname]($style) '

[directory]
style = 'bold {{ accent }}'
truncation_length = 4
truncation_symbol = '…/'
truncate_to_repo = true
read_only = ' '
read_only_style = '{{ color1 }}'

[git_branch]
symbol = ' '
style = '{{ color5 }}'
format = '[$symbol$branch]($style) '

# Mid-operation state: REBASING 1/4, MERGING, REVERTING, …
[git_state]
style = 'bold {{ color1 }}'
format = '[\($state( $progress_current/$progress_total)\)]($style) '

[git_status]
style = '{{ color3 }}'
format = '([\[$all_status$ahead_behind\]]($style)) '

# Active direnv / nix shell — context most prompts hide.
[direnv]
disabled = false
symbol = ' '
style = '{{ color3 }}'
format = '[$symbol$loaded]($style) '

[nix_shell]
symbol = ' '
style = '{{ color4 }}'
format = '[$symbol$state( \($name\))]($style) '

# Project version pulled from the manifest (Cargo.toml, package.json,
# pyproject.toml, …). Only shows inside a recognised package.
[package]
symbol = ' '
style = '{{ color8 }}'
format = '[$symbol$version]($style) '

[docker_context]
symbol = ' '
style = '{{ color4 }}'
format = '[$symbol$context]($style) '
# Don't show the default local context — only meaningful overrides.
only_with_files = true

# Kubernetes context + namespace. Renders whenever a kube context is
# set; flip `disabled = true` if you don't want it following you around.
[kubernetes]
disabled = false
symbol = '☸ '
style = '{{ color4 }}'
format = '[$symbol$context( \($namespace\))]($style) '

[cmd_duration]
min_time = 2_000
format = '[ $duration]({{ color8 }}) '

[nodejs]
symbol = ' '
style = '{{ color2 }}'
format = '[$symbol($version )]($style)'

[deno]
style = '{{ color4 }}'
format = '[$symbol($version )]($style)'

[bun]
style = '{{ color5 }}'
format = '[$symbol($version )]($style)'

[python]
symbol = ' '
style = '{{ color3 }}'
format = '[$symbol($version )(\($virtualenv\) )]($style)'

[rust]
symbol = ' '
style = '{{ color1 }}'
format = '[$symbol($version )]($style)'

[golang]
symbol = ' '
style = '{{ color6 }}'
format = '[$symbol($version )]($style)'

[lua]
symbol = ' '
style = '{{ color4 }}'
format = '[$symbol($version )]($style)'

[java]
symbol = ' '
style = '{{ color1 }}'
format = '[$symbol($version )]($style)'

[kotlin]
symbol = ' '
style = '{{ color5 }}'
format = '[$symbol($version )]($style)'

[ruby]
symbol = ' '
style = '{{ color1 }}'
format = '[$symbol($version )]($style)'

[php]
symbol = ' '
style = '{{ color4 }}'
format = '[$symbol($version )]($style)'

[dotnet]
symbol = '.NET '
style = '{{ color5 }}'
format = '[$symbol($version )(🎯 $tfm )]($style)'

[zig]
symbol = ' '
style = '{{ color3 }}'
format = '[$symbol($version )]($style)'

[elixir]
symbol = ' '
style = '{{ color5 }}'
format = '[$symbol($version )]($style)'

[swift]
symbol = ' '
style = '{{ color1 }}'
format = '[$symbol($version )]($style)'

[haskell]
symbol = ' '
style = '{{ color5 }}'
format = '[$symbol($version )]($style)'

[c]
symbol = ' '
style = '{{ color4 }}'
format = '[$symbol($version(-$name) )]($style)'
