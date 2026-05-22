#!/bin/bash
# install/plymouth.sh — Plymouth theme + mkinitcpio HOOKS rewrite +
# UKI splash replacement.
#
# Implements docs/install-steps.md §11 + §11a + §11b.
#
# Runs unattended per user choice. The fragile step is the LUKS
# cmdline rewrite — guarded behind LUKS auto-detection.
#
# What we do, in order:
#   1. Install Plymouth theme files (always).
#   2. Detect LUKS via current cmdline / bootloader / crypttab.
#   3. Rewrite /etc/mkinitcpio.conf HOOKS line idempotently
#      (always — sd-encrypt no-ops cleanly when no rd.luks.name= is
#      passed, so we keep one HOOKS line that works for both LUKS
#      and non-LUKS systems).
#   4. If LUKS detected, swap cryptdevice=UUID=<uuid>:root for
#      rd.luks.name=<uuid>=root in every bootloader cmdline source
#      we recognise (limine, systemd-boot, mkinitcpio UKI presets).
#   5. UKI splash replacement (only if the preset file references the
#      stock Arch splash).
#   6. plymouth-set-default-theme + mkinitcpio -P to bake the result.
#
# This file is sourced; plymouth_setup() is the entrypoint.

if [[ -n ${NIRIMAKI_PLYMOUTH_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_PLYMOUTH_LOADED=1

# 1. Install the theme files.
_pm_install_theme() {
  section "Plymouth: install qs-minimal theme (§11)"
  sudo install -d /usr/share/plymouth/themes/qs-minimal
  # `install -m 644` per file rather than `cp` to set perms deterministically.
  local src
  for src in "$REPO_DIR"/assets/plymouth/*; do
    [[ -f $src ]] || continue
    sudo install -m 644 "$src" "/usr/share/plymouth/themes/qs-minimal/$(basename "$src")"
  done
  ok "theme files installed under /usr/share/plymouth/themes/qs-minimal/"
}

# 2. LUKS detection.
#
# We check four sources and call it LUKS-active if ANY shows a crypt
# device for root. False positives are safer than false negatives —
# rewriting cmdline on a non-LUKS box does nothing dangerous, but
# skipping it on a LUKS box can render the next boot unable to find
# its root device.
#
# Returns:
#   0 if LUKS detected
#   1 otherwise
# Sets NIRIMAKI_LUKS_UUID if it could parse the UUID.
_pm_luks_detect() {
  NIRIMAKI_LUKS_UUID=""

  # a) /proc/cmdline — what the running kernel was given.
  if grep -qE '(^|[[:space:]])(cryptdevice|rd\.luks\.name|rd\.luks\.uuid)=' /proc/cmdline 2>/dev/null; then
    NIRIMAKI_LUKS_UUID="$(awk '
      {
        for (i = 1; i <= NF; i++) {
          if (match($i, /cryptdevice=UUID=([^: ]+)/, m)) { print m[1]; exit }
          if (match($i, /cryptdevice=\/dev\/disk\/by-uuid\/([^: ]+)/, m)) { print m[1]; exit }
          if (match($i, /rd\.luks\.name=([^= ]+)=root/, m)) { print m[1]; exit }
          if (match($i, /rd\.luks\.uuid=([^ ]+)/, m)) { print m[1]; exit }
        }
      }
    ' /proc/cmdline)"
    return 0
  fi

  # b) /etc/crypttab non-comment entries — long-term truth.
  if [[ -f /etc/crypttab ]] && grep -qE '^[^#[:space:]]+[[:space:]]+UUID=' /etc/crypttab; then
    NIRIMAKI_LUKS_UUID="$(awk '$1 !~ /^#/ && $2 ~ /^UUID=/ { sub("UUID=", "", $2); print $2; exit }' /etc/crypttab)"
    return 0
  fi

  # c) Any bootloader config file mentioning cryptdevice= / rd.luks.name=.
  local f
  for f in /etc/kernel/cmdline /etc/cmdline.d/*.conf \
           /boot/loader/entries/*.conf /efi/loader/entries/*.conf \
           /boot/limine.conf /boot/limine/limine.conf \
           /etc/default/grub; do
    [[ -f $f ]] || continue
    if grep -qE '(cryptdevice|rd\.luks\.name|rd\.luks\.uuid)=' "$f"; then
      NIRIMAKI_LUKS_UUID="$(grep -oE 'cryptdevice=UUID=[^: [:space:]"]+|rd\.luks\.name=[^= ]+=root|rd\.luks\.uuid=[^ "]+' "$f" \
        | head -1 \
        | sed -E 's|cryptdevice=UUID=||; s|rd\.luks\.name=||; s|=root$||; s|rd\.luks\.uuid=||')"
      return 0
    fi
  done

  return 1
}

# 3. Rewrite the HOOKS line in /etc/mkinitcpio.conf.
#
# Idempotent — sed match-and-replace handles re-runs cleanly.
# Backs up first so a misparse is recoverable.
_pm_hooks_rewrite() {
  section "Plymouth: mkinitcpio HOOKS rewrite (§11a)"
  local conf=/etc/mkinitcpio.conf
  local target='HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)'
  local current
  current="$(sudo grep -E '^HOOKS=' "$conf" || true)"
  if [[ $current == "$target" ]]; then
    ok "HOOKS line already correct"
    return 0
  fi
  sudo cp -n "$conf" "$conf.nirimaki-bak"
  sudo sed -i "s|^HOOKS=.*|$target|" "$conf"
  ok "rewrote $conf HOOKS line (backup at $conf.nirimaki-bak)"
}

# 4. LUKS cmdline swap: cryptdevice=UUID=<uuid>:root → rd.luks.name=<uuid>=root.
#
# Touches every file we recognise; backs each one up first.
# Skip silently if no UUID could be parsed (defensive — running this
# blind would break boot).
_pm_luks_cmdline_swap() {
  if [[ -z $NIRIMAKI_LUKS_UUID ]]; then
    warn "LUKS active but UUID couldn't be parsed — skipping cmdline swap. Edit your bootloader manually."
    return 0
  fi
  section "Plymouth: LUKS cmdline swap (uuid=$NIRIMAKI_LUKS_UUID)"

  local f changed=0
  for f in /etc/kernel/cmdline /etc/cmdline.d/*.conf \
           /boot/loader/entries/*.conf /efi/loader/entries/*.conf \
           /boot/limine.conf /boot/limine/limine.conf \
           /etc/default/grub; do
    [[ -f $f ]] || continue
    if grep -qE "cryptdevice=(UUID=)?$NIRIMAKI_LUKS_UUID:root" "$f"; then
      sudo cp -n "$f" "$f.nirimaki-bak"
      # Swap cryptdevice=UUID=<uuid>:root → rd.luks.name=<uuid>=root.
      # root=/dev/mapper/root is typically already on the cmdline next
      # to cryptdevice= (encrypt hook needs it explicitly), so we don't
      # add it — that would duplicate the arg.
      sudo sed -i -E "s|cryptdevice=(UUID=)?$NIRIMAKI_LUKS_UUID:root|rd.luks.name=$NIRIMAKI_LUKS_UUID=root|g" "$f"
      ok "rewrote cmdline in $f (backup at $f.nirimaki-bak)"
      changed=1
    elif grep -qE "rd.luks.name=$NIRIMAKI_LUKS_UUID=root" "$f"; then
      ok "$f already uses rd.luks.name= (no change)"
      changed=1
    fi
  done

  # GRUB: cmdline doesn't appear in the user-visible /boot/grub/grub.cfg
  # — it's templated from /etc/default/grub. Tell the user to regenerate.
  if [[ -f /etc/default/grub ]] && grep -qE 'cryptdevice|rd\.luks\.name' /etc/default/grub; then
    warn "/etc/default/grub touched — remember to run 'sudo grub-mkconfig -o /boot/grub/grub.cfg'."
  fi

  if (( ! changed )); then
    warn "LUKS detected but no recognised cmdline file matched the UUID. Verify your bootloader manually."
  fi
}

# 5. UKI splash replacement — only when the preset references the
# stock Arch splash. systemd-boot non-UKI setups won't have this file,
# and ad-hoc setups may already use a custom splash.
_pm_uki_splash() {
  section "Plymouth: UKI splash replacement (§11b)"
  sudo install -Dm644 "$REPO_DIR/assets/splash.bmp" /usr/share/nirimaki/splash.bmp

  local preset=/etc/mkinitcpio.d/linux.preset
  if [[ ! -f $preset ]]; then
    ok "no $preset — skipping UKI splash hookup (not a UKI setup)"
    return 0
  fi
  if grep -q '/usr/share/nirimaki/splash.bmp' "$preset"; then
    ok "$preset already points at the Nirimaki splash"
    return 0
  fi
  if grep -q '/usr/share/systemd/bootctl/splash-arch.bmp' "$preset"; then
    sudo cp -n "$preset" "$preset.nirimaki-bak"
    sudo sed -i 's|/usr/share/systemd/bootctl/splash-arch.bmp|/usr/share/nirimaki/splash.bmp|' "$preset"
    ok "rewrote $preset to use /usr/share/nirimaki/splash.bmp (backup at $preset.nirimaki-bak)"
  else
    warn "$preset doesn't reference the stock splash — leaving as-is. Edit manually if you want the Nirimaki splash."
  fi
}

# 6. Set default plymouth theme + rebuild initramfs (always last).
_pm_finalise() {
  section "Plymouth: set theme + mkinitcpio -P"
  sudo plymouth-set-default-theme qs-minimal
  ok "default Plymouth theme = qs-minimal"
  info "rebuilding initramfs (mkinitcpio -P) — this can take a minute"
  sudo mkinitcpio -P
  ok "initramfs rebuilt"

  # mkinitcpio rebuild typically lands a new kernel image → flag reboot.
  NIRIMAKI_NEEDS_REBOOT=1
  NIRIMAKI_REBOOT_REASON+=("Plymouth + initramfs")
}

plymouth_setup() {
  _pm_install_theme

  if _pm_luks_detect; then
    info "LUKS detected (uuid=${NIRIMAKI_LUKS_UUID:-?}) — will swap cryptdevice→rd.luks.name."
    _pm_hooks_rewrite
    _pm_luks_cmdline_swap
  else
    info "No LUKS detected — installing splash + HOOKS rewrite without cmdline swap. SDDM autologin will NOT be enabled."
    _pm_hooks_rewrite
  fi
  _pm_uki_splash
  _pm_finalise
}
