echo "Install capitaine-cursors + re-apply theme for a consistent cursor"
#
# Why: nirimaki-theme-set now drives a single cursor theme (Capitaine),
# picking the light (white) variant for dark themes and the dark (black)
# one for light themes. niri renders it and exports XCURSOR_THEME/SIZE
# to children; theme-set also mirrors it into gsettings, GTK
# settings.ini, and ~/.icons/default/index.theme. Existing installs
# lack the package — without it niri logs "no default icon" and falls
# back to its built-in pointer. Install it, then re-apply the active
# theme so all surfaces get written.
#
# capitaine-cursors lives in the official `extra` repo (not AUR), so it
# installs to /usr/share/icons — on the default XCURSOR_PATH. Both
# variants (capitaine-cursors, capitaine-cursors-light) ship in the one
# package.
#
# Idempotent: pacman --needed no-ops when present; re-applying the
# current theme is always safe.

echo "  installing capitaine-cursors (if missing)"
sudo pacman -S --needed --noconfirm capitaine-cursors || true

cur=$(cat "$HOME/.config/theme/current/theme.name" 2>/dev/null || true)
if [[ -n $cur ]] && command -v nirimaki-theme-set >/dev/null 2>&1; then
  echo "  re-applying theme '$cur' to write cursor settings"
  nirimaki-theme-set "$cur" >/dev/null 2>&1 || true
fi

# niri caches the cursor theme and does NOT hot-swap the live pointer on
# config reload — the new cursor takes effect on the next niri restart /
# relogin. Nothing to force here; just a heads-up that the change is not
# instant on a running session.
echo "  note: the new cursor applies after the next relogin"
