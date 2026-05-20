# lazygit config — rendered by qs-theme-set from the active theme's
# colors.toml. The active border uses Nirimaki's accent (varies per
# theme); everything else uses lazygit's ANSI-named defaults so the
# rest of the UI follows the kitty terminal palette automatically
# (same trick as bat / delta / tmux).
#
# Lazygit reads its config at startup, so a theme swap is reflected
# the next time you launch lazygit (no live re-tint).

gui:
  theme:
    activeBorderColor:
      - "{{ accent }}"
      - bold
    inactiveBorderColor:
      - white
    optionsTextColor:
      - blue
    selectedLineBgColor:
      - default
      - reverse
    cherryPickedCommitBgColor:
      - cyan
    cherryPickedCommitFgColor:
      - blue
    unstagedChangesColor:
      - red
    defaultFgColor:
      - default
