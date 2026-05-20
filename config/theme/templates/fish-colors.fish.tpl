# fish-colors.fish — Nirimaki theme → fish syntax highlight palette.
#
# Rendered by qs-theme-set from the active theme's colors.toml.
# Applied via `set -U` (universal variables) so changes propagate to
# every running fish instance instantly, not just new sessions.
# Sourced on shell startup from conf.d/tools.fish as a safety net.
#
# Color tokens come from theme colors.toml: foreground, background,
# selection_foreground, selection_background, color0..color15, accent.
# qs-theme-set's `{{ key_strip }}` substitution removes the leading
# `#` so the hex values match fish's expected format.

# --- code highlighting -------------------------------------------------
set -U fish_color_normal        {{ foreground_strip }}
set -U fish_color_command       {{ color2_strip }}
set -U fish_color_keyword       {{ color4_strip }}
set -U fish_color_param         {{ color3_strip }}
set -U fish_color_option        {{ color6_strip }}
set -U fish_color_quote         {{ color3_strip }}
set -U fish_color_redirection   {{ color5_strip }}
set -U fish_color_operator      {{ color5_strip }}
set -U fish_color_end           {{ color5_strip }}
set -U fish_color_error         {{ color1_strip }}
set -U fish_color_comment       {{ color8_strip }}
set -U fish_color_escape        {{ color6_strip }}
set -U fish_color_autosuggestion {{ color8_strip }}

# --- interactive UI ----------------------------------------------------
# Match (paren highlight) + search-match — accent on bg for contrast.
set -U fish_color_match         {{ accent_strip }}
set -U fish_color_search_match  --background={{ accent_strip }} {{ background_strip }}
set -U fish_color_selection     --background={{ selection_background_strip }} {{ selection_foreground_strip }}
set -U fish_color_history_current {{ accent_strip }}
set -U fish_color_cancel        {{ color1_strip }}
set -U fish_color_valid_path    --underline

# --- pager (tab completion) -------------------------------------------
set -U fish_pager_color_progress {{ color8_strip }}
set -U fish_pager_color_prefix   {{ accent_strip }} --bold
set -U fish_pager_color_completion {{ foreground_strip }}
set -U fish_pager_color_description {{ color8_strip }}
set -U fish_pager_color_selected_background --background={{ accent_strip }}
set -U fish_pager_color_selected_completion {{ background_strip }}
set -U fish_pager_color_selected_description {{ background_strip }}
