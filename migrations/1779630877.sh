echo "Install zen-browser-bin (missed by earlier install.sh)"
#
# Why: install/packaging.sh _pkg_browsers used to only install
# chromium + firefox and *assume* Zen might be present from
# somewhere — but install.sh never actually pulled it. Existing
# Nirimaki boxes ended up with Firefox as the default browser
# even though the rest of the stack (browser-launch, webapp-launch,
# nirimaki-browser-default) treats Zen as the primary. This
# migration backfills the package only — does NOT change the
# user's chosen default browser, since by now they may have
# deliberately picked one.

if command -v zen-browser >/dev/null 2>&1 || pacman -Q zen-browser-bin >/dev/null 2>&1; then
  echo "  zen-browser-bin already installed — skipping"
  exit 0
fi

if ! command -v paru >/dev/null 2>&1; then
  echo "  paru not on PATH — cannot install AUR package; skipping" >&2
  exit 1
fi

paru -S --needed --noconfirm --skipreview zen-browser-bin
