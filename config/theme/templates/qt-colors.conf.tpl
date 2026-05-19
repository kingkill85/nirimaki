; Qt platform palette rendered from ~/.config/theme/current/colors.toml.
; Read by qt5ct and qt6ct via `color_scheme_path` (set once in their
; main config; we just rewrite this file on every theme swap).
;
; The 21-colour row order is the Qt::ColorRole sequence used by
; qt5ct/qt6ct:
;   1  WindowText           12  Shadow
;   2  Button               13  Highlight
;   3  Light                14  HighlightedText
;   4  Midlight             15  Link
;   5  Dark                 16  LinkVisited
;   6  Mid                  17  AlternateBase
;   7  Text                 18  NoRole
;   8  BrightText           19  ToolTipBase
;   9  ButtonText           20  ToolTipText
;   10 Base                 21  PlaceholderText
;   11 Window
;
; Format per entry is #aarrggbb (alpha first); we prepend `ff` to the
; theme's hex tokens.

[ColorScheme]
active_colors=#ff{{ foreground_strip }}, #ff{{ background_strip }}, #ff{{ color0_strip }}, #ff{{ color0_strip }}, #ff{{ color8_strip }}, #ff{{ color8_strip }}, #ff{{ foreground_strip }}, #ff{{ color1_strip }}, #ff{{ foreground_strip }}, #ff{{ background_strip }}, #ff{{ background_strip }}, #ff000000, #ff{{ accent_strip }}, #ff{{ background_strip }}, #ff{{ color4_strip }}, #ff{{ color5_strip }}, #ff{{ color0_strip }}, #ff000000, #ff{{ color0_strip }}, #ff{{ foreground_strip }}, #ff{{ color8_strip }}
disabled_colors=#ff{{ color8_strip }}, #ff{{ background_strip }}, #ff{{ color0_strip }}, #ff{{ color0_strip }}, #ff{{ color8_strip }}, #ff{{ color8_strip }}, #ff{{ color8_strip }}, #ff{{ color1_strip }}, #ff{{ color8_strip }}, #ff{{ background_strip }}, #ff{{ background_strip }}, #ff000000, #ff{{ color8_strip }}, #ff{{ background_strip }}, #ff{{ color8_strip }}, #ff{{ color5_strip }}, #ff{{ color0_strip }}, #ff000000, #ff{{ color0_strip }}, #ff{{ foreground_strip }}, #ff{{ color8_strip }}
inactive_colors=#ff{{ foreground_strip }}, #ff{{ background_strip }}, #ff{{ color0_strip }}, #ff{{ color0_strip }}, #ff{{ color8_strip }}, #ff{{ color8_strip }}, #ff{{ foreground_strip }}, #ff{{ color1_strip }}, #ff{{ foreground_strip }}, #ff{{ background_strip }}, #ff{{ background_strip }}, #ff000000, #ff{{ color8_strip }}, #ff{{ foreground_strip }}, #ff{{ color4_strip }}, #ff{{ color5_strip }}, #ff{{ color0_strip }}, #ff000000, #ff{{ color0_strip }}, #ff{{ foreground_strip }}, #ff{{ color8_strip }}
