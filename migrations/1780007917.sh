echo "Regenerate GTK settings.ini so app window chrome picks up dark mode (Bitwarden et al.)"
#
# Why: nirimaki-theme-set now CREATES ~/.config/gtk-3.0/settings.ini and
# gtk-4.0/settings.ini with gtk-application-prefer-dark-theme. Previously
# it only edited those files if they already existed, so a fresh install
# never got the dark flag — GTK-chrome apps (Electron / libdecor window
# decorations + native menu bars, e.g. Bitwarden's top bar) stayed light
# even though the freedesktop portal correctly reported prefer-dark
# (which is why browsers were fine). Re-apply the current theme so the
# files get written on existing installs.
#
# Idempotent — re-applying the same theme just rewrites the same outputs.

THEME_NAME_FILE="$HOME/.config/theme/current/theme.name"

if [[ -r $THEME_NAME_FILE && -x $HOME/.local/bin/nirimaki-theme-set ]]; then
  name=$(< "$THEME_NAME_FILE")
  echo "  re-applying theme '$name' to (re)write GTK settings.ini"
  "$HOME/.local/bin/nirimaki-theme-set" "$name" >/dev/null 2>&1 || true
else
  echo "  skip: no current theme recorded (fresh install handles it natively)"
fi
