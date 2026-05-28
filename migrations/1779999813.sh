echo "Install mpv + register it as the default video player"
#
# Why: mpv is now part of the §2b GUI baseline (install/packaging.sh) and
# seeded as the default handler for the common video MIME types in
# install/assets/mimeapps.list.tpl. Fresh installs get both natively;
# this backfills existing boxes — git pull alone installs no package and
# won't re-template ~/.config/mimeapps.list.
#
# Idempotent: pacman -S --needed skips an already-installed mpv;
# `xdg-mime default` only rewrites the video/* lines, leaving the user's
# browser and other associations untouched.

if ! pacman -Qq mpv >/dev/null 2>&1; then
  echo "  installing mpv"
  sudo pacman -S --needed --noconfirm mpv
else
  echo "  mpv already installed"
fi

# Register mpv for the same video types the install-time template seeds.
echo "  setting mpv as default video handler"
xdg-mime default mpv.desktop \
  video/mp4 \
  video/x-matroska \
  video/webm \
  video/x-msvideo \
  video/quicktime \
  video/mpeg \
  video/x-flv \
  video/3gpp \
  video/ogg \
  video/x-ogm+ogg >/dev/null 2>&1 || true
