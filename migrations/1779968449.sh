echo "Install gvfs + gvfs-smb (file-manager SMB support)"
#
# Why: Nautilus and other GIO-based file managers need gvfs-smb to
# resolve `smb://host/share` URIs. Without it, opening such a URI
# silently fails. Standard expectation on a desktop install — add to
# the GUI baseline.
#
# gvfs pulls in the trash / network / cdda / mtp backends as deps;
# gvfs-smb adds the SMB backend on top.
#
# Idempotent — `pacman -S --needed` skips already-installed packages.

if command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm gvfs gvfs-smb
fi
