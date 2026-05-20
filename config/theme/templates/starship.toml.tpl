# starship.toml — Nirimaki themed prompt.
#
# Rendered by qs-theme-set from this template + the active theme's
# colors.toml. {{ key }} placeholders are substituted with hex colours
# (with leading `#`). Starship rereads this file on every prompt
# redraw, so a theme swap shows up on the next Enter — no signal
# needed.
#
# Layout: two lines.
#   line 1: cwd · git · runtime versions · cmd duration
#   line 2: prompt character — always at column 0 no matter how much
#           state appeared above

add_newline = false

format = """
$directory\
$git_branch\
$git_status\
$nodejs\
$python\
$rust\
$golang\
$lua\
$cmd_duration\
$line_break\
$character\
"""

[character]
success_symbol = '[❯](bold {{ color2 }})'
error_symbol = '[❯](bold {{ color1 }})'
vimcmd_symbol = '[❮](bold {{ color4 }})'

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

[git_status]
style = '{{ color3 }}'
format = '([\[$all_status$ahead_behind\]]($style)) '

[cmd_duration]
min_time = 2_000
format = '[ $duration]({{ color8 }}) '

[nodejs]
symbol = ' '
style = '{{ color2 }}'
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
