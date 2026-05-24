echo "Strip CachyOS preinstall conflicts (alacritty)"
#
# Why: CachyOS ships alacritty by default, which sits alongside foot
# (Nirimaki's chosen terminal) and confuses the picture — duplicate
# entries in tooling that enumerates terminals, extra disk weight,
# and a competing default. install.sh now removes it on fresh boxes;
# this migration does the same for existing Nirimaki installs.
# Conditional, so non-CachyOS Arch boxes that never had it are a no-op.

removed=0
for pkg in alacritty; do
  if pacman -Qq "$pkg" >/dev/null 2>&1; then
    echo "  removing $pkg"
    sudo pacman -R --noconfirm "$pkg"
    removed=$((removed + 1))
  fi
done

if (( removed == 0 )); then
  echo "  no conflicts present — skipping"
fi
