echo "btop — set color_theme=\"qs\" in btop.conf so it picks up the nirimaki theme"
#
# Why: nirimaki-theme-set has always installed ~/.config/btop/themes/qs.theme,
# but on a fresh box btop.conf doesn't exist yet — btop creates it on first
# launch with color_theme="Default" and ignores our file. Result: unstyled
# btop. Fixed in nirimaki-theme-set going forward; this backfills the line
# into btop.conf on existing installs.

set -e

conf="$HOME/.config/btop/btop.conf"
theme="$HOME/.config/btop/themes/qs.theme"

if [[ ! -f $theme ]]; then
  echo "  qs.theme not installed yet — skipping (run 'nirimaki theme set <name>' first)"
  exit 0
fi

mkdir -p "$(dirname "$conf")"

if [[ ! -f $conf ]]; then
  printf 'color_theme = "qs"\n' > "$conf"
  echo "  wrote new btop.conf with color_theme=qs"
elif ! grep -qE '^[[:space:]]*color_theme[[:space:]]*=[[:space:]]*"qs"' "$conf"; then
  if grep -qE '^[[:space:]]*color_theme[[:space:]]*=' "$conf"; then
    sed -i -E 's|^[[:space:]]*color_theme[[:space:]]*=.*|color_theme = "qs"|' "$conf"
    echo "  updated color_theme line in btop.conf"
  else
    printf 'color_theme = "qs"\n' >> "$conf"
    echo "  appended color_theme line to btop.conf"
  fi
else
  echo "  btop already configured for qs theme"
fi
