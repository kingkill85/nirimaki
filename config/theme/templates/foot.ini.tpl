# foot terminal colours + alpha, rendered by qs-theme-set from
# ~/.config/theme/current/colors.toml. Sourced by config/foot/foot.ini
# via its trailing `include=~/.config/theme/current/foot.ini`.
#
# Foot wants `aabbcc` without the leading `#`, so every colour uses
# the `{{ key_strip }}` variant qs-theme-set generates.
#
# foot 1.27 split [colors] into [colors-dark] (active when the
# freedesktop color-scheme preference is dark) and [colors-light]
# (active when light). qs-theme-set sets that preference per theme,
# but to keep the visual identity consistent regardless we emit the
# SAME palette into both sections — Nirimaki owns the look, not the
# system.

[colors-dark]
# alpha=0.99 forces foot to allocate an RGBA buffer so niri's opacity
# multiplier (window-rules in config.kdl) actually applies — opaque RGB
# framebuffers ignore the multiplier on AMD (niri#2346). The visible
# translucency comes from the niri rule, not from foot.
alpha=0.99

foreground={{ foreground_strip }}
background={{ background_strip }}
selection-foreground={{ selection_foreground_strip }}
selection-background={{ selection_background_strip }}

# `cursor=TEXT-UNDER-CURSOR CURSOR` — foot moved cursor color out
# of the [cursor] section into [colors-*] (the [cursor] section is
# only for style / blink / thickness).
cursor={{ background_strip }} {{ cursor_strip }}

regular0={{ color0_strip }}
regular1={{ color1_strip }}
regular2={{ color2_strip }}
regular3={{ color3_strip }}
regular4={{ color4_strip }}
regular5={{ color5_strip }}
regular6={{ color6_strip }}
regular7={{ color7_strip }}

bright0={{ color8_strip }}
bright1={{ color9_strip }}
bright2={{ color10_strip }}
bright3={{ color11_strip }}
bright4={{ color12_strip }}
bright5={{ color13_strip }}
bright6={{ color14_strip }}
bright7={{ color15_strip }}

[colors-light]
alpha=0.99

foreground={{ foreground_strip }}
background={{ background_strip }}
selection-foreground={{ selection_foreground_strip }}
selection-background={{ selection_background_strip }}

cursor={{ background_strip }} {{ cursor_strip }}

regular0={{ color0_strip }}
regular1={{ color1_strip }}
regular2={{ color2_strip }}
regular3={{ color3_strip }}
regular4={{ color4_strip }}
regular5={{ color5_strip }}
regular6={{ color6_strip }}
regular7={{ color7_strip }}

bright0={{ color8_strip }}
bright1={{ color9_strip }}
bright2={{ color10_strip }}
bright3={{ color11_strip }}
bright4={{ color12_strip }}
bright5={{ color13_strip }}
bright6={{ color14_strip }}
bright7={{ color15_strip }}
