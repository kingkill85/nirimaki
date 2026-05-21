# yazi theme.toml — Nirimaki overrides.
#
# Rendered by qs-theme-set from the active theme's colors.toml.
# yazi reads ~/.config/yazi/theme.toml at startup; a theme swap is
# reflected on the next yazi launch.
#
# Strategy: override only the accent-tied surfaces (cwd path,
# active tab, active mode, focused selection) with Nirimaki's accent
# hex. Everything else stays unset so yazi falls back to its preset
# theme — which uses ANSI named colours that already track the foot
# palette → that's the same indirect-follow story bat / delta / tmux
# use.

[mgr]
cwd = { fg = "{{ accent }}", bold = true }

# Marker bar on the left edge of selected / cut / copied files. Keep
# ANSI defaults — they already render distinct against any background.
marker_copied   = { fg = "lightgreen",  bg = "lightgreen" }
marker_cut      = { fg = "lightred",    bg = "lightred" }
marker_marked   = { fg = "lightcyan",   bg = "lightcyan" }
marker_selected = { fg = "{{ accent }}", bg = "{{ accent }}" }
marker_symbol   = "│"

# Find-mode highlight
find_keyword  = { fg = "{{ color3 }}", bold = true, italic = true, underline = true }
find_position = { fg = "{{ color5 }}", bg = "reset", bold = true, italic = true }

# Window border
border_symbol = "│"
border_style  = { fg = "{{ color8 }}" }

[tabs]
active   = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
inactive = { fg = "{{ foreground }}", bg = "{{ color0 }}" }
sep_inner = { open = "", close = "" }
sep_outer = { open = "", close = "" }

[mode]
normal_main = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
normal_alt  = { fg = "{{ accent }}", bg = "{{ color0 }}" }

select_main = { fg = "{{ background }}", bg = "{{ color3 }}", bold = true }
select_alt  = { fg = "{{ color3 }}", bg = "{{ color0 }}" }

unset_main  = { fg = "{{ background }}", bg = "{{ color1 }}", bold = true }
unset_alt   = { fg = "{{ color1 }}", bg = "{{ color0 }}" }

[status]
sep_left  = { open = "", close = "" }
sep_right = { open = "", close = "" }

# Progress indicator (bottom-right when a task runs)
progress_label  = { fg = "{{ background }}", bold = true }
progress_normal = { fg = "{{ accent }}", bg = "{{ color0 }}" }
progress_error  = { fg = "{{ color1 }}", bg = "{{ color0 }}" }

# Permission row colours (rwx triplet)
perm_type   = { fg = "{{ color4 }}" }
perm_read   = { fg = "{{ color3 }}" }
perm_write  = { fg = "{{ color1 }}" }
perm_exec   = { fg = "{{ color2 }}" }
perm_sep    = { fg = "{{ color8 }}" }

[which]
mask      = { bg = "{{ color0 }}" }
cand      = { fg = "{{ color6 }}" }
rest      = { fg = "{{ color8 }}" }
desc      = { fg = "{{ color5 }}" }
separator = " ➜ "
separator_style = { fg = "{{ color8 }}" }

[input]
border   = { fg = "{{ accent }}" }
title    = {}
value    = {}
selected = { reversed = true }

[confirm]
border  = { fg = "{{ accent }}" }
title   = { fg = "{{ accent }}" }
content = {}
list    = {}
btn_yes = { reversed = true }
btn_no  = {}

[pick]
border   = { fg = "{{ accent }}" }
active   = { fg = "{{ color5 }}" }
inactive = {}

[notify]
title_info  = { fg = "{{ color2 }}" }
title_warn  = { fg = "{{ color3 }}" }
title_error = { fg = "{{ color1 }}" }

# Folder icon colours. yazi's preset uses hardcoded fixed hex (#03a9f4
# cyan for generic dirs, #ff9800 orange for .config, etc.) that ignore
# whatever theme you pick. We replace the catch-all `dir` cond with
# Nirimaki accent, and blank out the named-dir overrides so every
# folder uses the accent uniformly. Glyphs themselves are unchanged —
# yazi still pulls its nerd-font folder/git/etc. icons; only the
# colour tracks the theme.
#
# Glyphs are written as \uXXXX TOML escapes (rather than the raw
# nerd-font character) so the template survives copy/paste cleanly.
# Codepoints sourced from yazi's preset theme-dark.toml:
#   orphan U+F127  link U+F481  block U+F0C9  char U+F1C0  fifo U+F1D1
#   sock U+F1E4  sticky U+F08D  dummy U+F057  dir-hover U+E5FE
#   dir U+E5FF  exec U+F489  file U+F15B
[icon]
dirs = []
conds = [
  { if = "orphan",        text = "", fg = "{{ color8 }}" },
  { if = "link",          text = "", fg = "{{ color8 }}" },
  { if = "block",         text = "", fg = "{{ color3 }}" },
  { if = "char",          text = "", fg = "{{ color3 }}" },
  { if = "fifo",          text = "", fg = "{{ color3 }}" },
  { if = "sock",          text = "", fg = "{{ color3 }}" },
  { if = "sticky",        text = "", fg = "{{ color3 }}" },
  { if = "dummy",         text = "", fg = "{{ color1 }}" },
  { if = "dir & hovered", text = "", fg = "{{ accent }}" },
  { if = "dir",           text = "", fg = "{{ accent }}" },
  { if = "exec",          text = "", fg = "{{ color2 }}" },
  { if = "!dir",          text = "", fg = "{{ foreground }}" },
]
