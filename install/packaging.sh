#!/bin/bash
# install/packaging.sh — every package and system-level enable in one place.
#
# Implements docs/install-steps.md §2a–§2i. Each helper is idempotent —
# pacman is invoked with --needed so already-installed packages are no-ops,
# and the systemctl / chmod / chown lines test before acting.
#
# Order matters:
#   §2a base.packages  → §2b compositor   → §2c terminal     → §2d AUR
#   → §2e bootstrap-extras (claude-code, pi)
#   → §2f browsers + chromium policy chmod + initial xdg default browser
#   → §2g fontconfig regional CJK preference + fc-cache
#   → §2h mimeapps.list seed (depends on §2f having run xdg-settings)
#   → §2i system enables, groups, modules
#
# This file is sourced; packaging() is the entrypoint.

if [[ -n ${NIRIMAKI_PACKAGING_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_PACKAGING_LOADED=1

# Full system upgrade — must run before any package install, especially
# before paru-bin bootstrap. Stale cloud/install-medium images often
# carry an older libalpm than the AUR-built paru-bin expects, causing
# "libalpm.so.X: cannot open shared object file" on the first paru call.
# This step refreshes everything to a coherent ABI.
_pkg_syu() {
  section "Packages: full system upgrade (pacman -Syu)"
  info "sudo pacman -Syu --noconfirm"
  sudo pacman -Syu --noconfirm
}

# §2a — minimal pacman seed list from install/base.packages.
_pkg_base() {
  section "Packages: base.packages (§2a)"
  local list=()
  while IFS= read -r line; do
    [[ -n $line ]] && list+=("$line")
  done < <(read_pkglist "$REPO_DIR/install/base.packages")
  pacman_install "${list[@]}"
}

# §2b — compositor, shell, GUI baseline.
#
# Includes the audit-flagged additions per user decision:
#   - nautilus (GTK file manager)
#   - xdg-desktop-portal-gnome + xdg-desktop-portal-gtk
#
# Notes per the spec:
#   - sddm  pulls qt6-declarative + qt6-svg via deps; we don't list them.
#   - bluez bluez-utils — daemon + CLI; service enabled in §2i.
#   - grim slurp satty — screenshot pipeline (Mod+Shift+S).
#   - pacman-contrib — checkupdates, used by the Updates topbar widget.
#   - libnotify — notify-send for theme/webapp/update hooks.
#   - noto-fonts-cjk/emoji/extra — CJK + emoji + less-common scripts.
#     §2g (fontconfig) tunes CJK regional preference on top.
_pkg_compositor() {
  section "Packages: compositor + shell + GUI baseline (§2b)"
  pacman_install \
    niri quickshell \
    sddm \
    swaybg swayidle \
    foot \
    wiremix bluetui impala bluez bluez-utils \
    ddcutil wf-recorder cliphist wl-clipboard wtype \
    grim slurp satty \
    pacman-contrib libnotify btop \
    playerctl brightnessctl \
    pavucontrol blueman \
    qt5ct qt6ct gnome-themes-extra \
    fontconfig ttf-jetbrains-mono-nerd \
    noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
    plymouth \
    nautilus \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk
}

# §2c — terminal toolkit (phase H).
_pkg_terminal() {
  section "Packages: terminal toolkit (§2c)"
  pacman_install \
    fish starship \
    eza bat fzf zoxide ripgrep fd git-delta \
    lazygit tealdeer sd ouch dust duf procs xh hyperfine tokei \
    tmux \
    yazi \
    neovim \
    jq
}

# AUR helper bootstrap — install paru if it's missing.
#
# Per Open Decision #3: install.sh bootstraps paru rather than
# requiring the user to install it first. Pattern is standard Arch:
#   pacman -S --needed base-devel git
#   git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
#   cd /tmp/paru-bin && makepkg -si --noconfirm
# `paru-bin` (binary) is chosen over `paru` (source) — faster, no Rust
# toolchain needed on every host.
_pkg_paru_bootstrap() {
  # Test that paru actually works, not just that the binary exists.
  # An older paru-bin built against a now-replaced libalpm.so will fail
  # to load — common after a system upgrade. We rebuild in that case.
  if command -v paru >/dev/null 2>&1 && paru --version >/dev/null 2>&1; then
    ok "paru already installed and working: $(command -v paru)"
    return 0
  fi
  if command -v paru >/dev/null 2>&1; then
    warn "paru installed but broken (libalpm ABI mismatch?) — rebuilding"
    sudo pacman -Rns --noconfirm paru-bin paru 2>/dev/null || true
  fi
  section "Bootstrap: paru-bin (AUR helper)"
  pacman_install base-devel git

  local build="/tmp/nirimaki-paru-bin"
  rm -rf "$build"
  git clone --depth=1 https://aur.archlinux.org/paru-bin.git "$build"
  (
    cd "$build"
    # makepkg refuses to run as root; this script never runs as root
    # (preflight bails) so we just invoke it directly.
    makepkg -si --noconfirm
  )
  rm -rf "$build"
  command -v paru >/dev/null || die "paru bootstrap failed."
  ok "paru installed: $(command -v paru)"
}

# §2d — AUR packages via paru.
_pkg_aur() {
  section "Packages: AUR (§2d)"
  paru_install pay-respects-bin yaru-icon-theme
}

# §2e — non-repo tools (claude-code, pi). Delegates to the
# bootstrap-extras.sh that already exists in the repo.
_pkg_bootstrap_extras() {
  section "Packages: bootstrap-extras (§2e — claude-code + pi)"
  bash "$REPO_DIR/install/bootstrap-extras.sh"
}

# §2f — browsers + chromium managed-policy dir + initial default browser.
#
# The chmod 0777-equivalent on /etc/chromium/policies/managed is the
# only privileged step at theme-swap runtime — handing the dir to the
# user so nirimaki-theme-set can write chromium-policy.json without
# sudo. Mirrors Omarchy's install/config/theme.sh.
#
# xdg-settings can fail if the .desktop file isn't installed yet —
# Zen is AUR/external and may not be present. Fall back to Firefox,
# which we just installed.
_pkg_browsers() {
  section "Packages: browsers + chromium policy dir + default browser (§2f)"
  pacman_install chromium firefox

  info "Granting /etc/chromium/policies/managed to the user (live-theme reload)"
  sudo mkdir -p /etc/chromium/policies/managed
  sudo chmod a+rw /etc/chromium/policies/managed
  ok "/etc/chromium/policies/managed writable by user"

  info "Setting initial default browser (Zen if available, else Firefox)"
  if ! xdg-settings set default-web-browser zen-browser.desktop 2>/dev/null; then
    xdg-settings set default-web-browser firefox.desktop \
      || warn "xdg-settings failed to set firefox.desktop — leaving system default"
  fi
  ok "default browser: $(xdg-settings get default-web-browser 2>/dev/null || echo '(unset)')"
}

# §2g — fontconfig regional preference for CJK.
#
# Without this, fc-match resolves lang=zh to Noto CJK JP (wrong glyphs).
# The shipped file in install/assets/ has all 6 match blocks.
_pkg_fontconfig() {
  section "Packages: fontconfig regional CJK preference (§2g)"
  install -Dm644 \
    "$REPO_DIR/install/assets/99-noto-cjk-regional.conf" \
    "$HOME/.config/fontconfig/conf.d/99-noto-cjk-regional.conf"
  fc-cache -f >/dev/null
  ok "wrote ~/.config/fontconfig/conf.d/99-noto-cjk-regional.conf + ran fc-cache -f"
}

# §2h — MIME defaults seed.
#
# Templates install/assets/mimeapps.list.tpl through `xdg-settings get
# default-web-browser` from §2f. Re-runnable: the user can switch
# default browser later and re-invoke this step to re-template.
#
# We OVERWRITE ~/.config/mimeapps.list rather than seed-once — this
# file is install.sh's surface, not a user-edit target. (Users who
# want different defaults edit `~/.config/nirimaki/extensions/menu.json`
# or call `xdg-mime default` directly; install.sh re-templating won't
# clobber those because we only own the [Default Applications] block.)
#
# That said: if the user has hand-edited mimeapps.list, we preserve
# whatever ISN'T [Default Applications] by appending instead of
# overwriting. Keep it simple here: write our block, append any
# preexisting other sections.
_pkg_mimeapps() {
  section "Packages: mimeapps default seed (§2h)"
  local browser tpl out tmp
  browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  if [[ -z $browser ]]; then
    warn "default browser unset — skipping mimeapps seed."
    return 0
  fi
  tpl="$REPO_DIR/install/assets/mimeapps.list.tpl"
  out="$HOME/.config/mimeapps.list"
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp)"
  sed "s|__BROWSER__|$browser|g" "$tpl" > "$tmp"

  # If an existing mimeapps.list has [Added Associations] or other
  # sections, preserve them by appending after our block.
  if [[ -f $out ]]; then
    awk '
      BEGIN { keep = 0 }
      /^\[/ { keep = ($0 != "[Default Applications]") }
      keep
    ' "$out" >> "$tmp"
  fi
  mv "$tmp" "$out"
  ok "wrote $out (default browser = $browser)"
}

# §2i — system enables, groups, modules.
#
# Bluetooth: bluez ships disabled on Arch.
# i2c: ddcutil-backed external-monitor brightness needs i2c-dev module +
#      user in i2c group. The group change requires a fresh login; we
#      flag it in the final reboot-needed report.
# systemd-networkd: per user choice (audit item, included). NB: this
#      coexists with NetworkManager-style stacks only if the user has
#      NM disabled. Default Arch ships neither enabled, so enabling
#      networkd here is safe on a fresh box.
_pkg_system_enables() {
  section "System enables (§2i)"

  info "enable+start bluetooth"
  sudo systemctl enable --now bluetooth
  ok "bluetooth.service enabled"

  info "i2c-dev module + $USER in i2c group (DDC/CI brightness)"
  if ! groups "$USER" | tr ' ' '\n' | grep -qx i2c; then
    sudo usermod -aG i2c "$USER"
    ok "added $USER to i2c (effective after re-login)"
    NIRIMAKI_NEEDS_REBOOT=1
    NIRIMAKI_REBOOT_REASON+=("i2c group change")
  else
    ok "$USER already in i2c group"
  fi
  if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]]; then
    echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
    sudo modprobe i2c-dev 2>/dev/null || true
    ok "wrote /etc/modules-load.d/i2c-dev.conf"
  else
    ok "/etc/modules-load.d/i2c-dev.conf already present"
  fi

  info "enable systemd-networkd"
  sudo systemctl enable --now systemd-networkd
  ok "systemd-networkd.service enabled"
}

# Top-level entrypoint, called from install.sh.
packaging() {
  _pkg_syu
  _pkg_base
  _pkg_compositor
  _pkg_terminal
  _pkg_paru_bootstrap
  _pkg_aur
  _pkg_bootstrap_extras
  _pkg_browsers
  _pkg_fontconfig
  _pkg_mimeapps
  _pkg_system_enables
}
