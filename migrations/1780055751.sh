echo "Install imv + evince and re-seed image/PDF/text MIME defaults"
#
# Why: Nirimaki now ships imv (image viewer) and evince (PDF viewer) and
# adds image/*, application/pdf, inode/directory and text/code MIME
# associations to mimeapps.list.tpl (Omarchy parity, minus mail). Fresh
# installs get this natively (packaging.sh §2b packages + §2h template);
# existing installs need the two packages plus a re-template of
# ~/.config/mimeapps.list.
#
# Idempotent: pacman --needed no-ops if present; re-templating rewrites
# only the [Default Applications] block and re-appends any other sections.

REPO="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"

# 1. Packages — both in the Arch official repos.
echo "  installing imv + evince (if missing)"
sudo pacman -S --needed --noconfirm imv evince || true

# 2. Re-template ~/.config/mimeapps.list against the current default
#    browser (mirrors install/packaging.sh _pkg_mimeapps).
tpl="$REPO/install/assets/mimeapps.list.tpl"
out="$HOME/.config/mimeapps.list"
if [[ ! -f $tpl ]]; then
  echo "  skip: template not found at $tpl"
else
  browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  [[ -z $browser ]] && browser="firefox.desktop"   # safe fallback; firefox is always installed
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp)"
  sed "s|__BROWSER__|$browser|g" "$tpl" > "$tmp"
  if [[ -f $out ]]; then
    # Preserve any non-[Default Applications] sections the user added.
    awk 'BEGIN{keep=0} /^\[/{keep=($0!="[Default Applications]")} keep' "$out" >> "$tmp"
  fi
  mv "$tmp" "$out"
  echo "  wrote $out (browser=$browser)"
  command -v update-desktop-database >/dev/null \
    && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi
