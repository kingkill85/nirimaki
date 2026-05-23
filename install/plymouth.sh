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
  section "Plymouth: install qs-minimal theme"
  sudo install -d /usr/share/plymouth/themes/qs-minimal
  # `install -m 644` per file rather than `cp` to set perms deterministically.
  local src
  for src in "$REPO_DIR"/assets/plymouth/*; do
    [[ -f $src ]] || continue
    sudo install -m 644 "$src" "/usr/share/plymouth/themes/qs-minimal/$(basename "$src")"
  done
  ok "theme files installed under /usr/share/plymouth/themes/qs-minimal/"
}

# 2. LUKS detection + UUID resolution.
#
# We need the *LUKS volume UUID* (from cryptsetup luksUUID), which is
# stored in the LUKS header. The kernel cmdline may refer to the crypt
# partition via several different identifiers though:
#
#   cryptdevice=UUID=<filesystem-uuid>:root      ← old encrypt hook
#   cryptdevice=PARTUUID=<gpt-partition-uuid>:root  ← archinstall+limine
#   cryptdevice=LABEL=<label>:root
#   cryptdevice=/dev/disk/by-uuid/<...>:root
#   cryptdevice=/dev/vda2:root
#   rd.luks.name=<luks-uuid>=root                ← sd-encrypt
#   rd.luks.uuid=<luks-uuid>                     ← sd-encrypt
#
# Only the rd.luks.* forms expose the LUKS UUID directly. Everything
# else points at the block device via *some* identifier — we resolve
# it to a /dev path with `findfs`, then ask cryptsetup for the LUKS
# UUID. PARTUUID ≠ LUKS UUID; treating them as the same was the bug
# that put PARTUUID installs into emergency mode.
#
# Returns:
#   0 if LUKS detected AND UUID resolved
#   1 otherwise
# Sets NIRIMAKI_LUKS_UUID on success.

# Resolve a cryptdevice= source ID to its LUKS volume UUID.
# $1 = the bit between cryptdevice= and :root (e.g. "PARTUUID=abc",
# "UUID=xxx", "/dev/vda2"). Echoes the LUKS UUID on stdout; non-zero
# rc if it couldn't be resolved.
_pm_resolve_luks_uuid() {
  local src="$1" dev=""
  case "$src" in
    UUID=*|PARTUUID=*|LABEL=*|PARTLABEL=*)
      dev=$(sudo findfs "$src" 2>/dev/null || true)
      ;;
    /dev/*)
      dev="$src"
      ;;
    *)
      return 1
      ;;
  esac
  [[ -n $dev && -b $dev ]] || return 1
  sudo cryptsetup isLuks "$dev" 2>/dev/null || return 1
  sudo cryptsetup luksUUID "$dev" 2>/dev/null
}

_pm_luks_detect() {
  NIRIMAKI_LUKS_UUID=""
  local raw=""

  # a) /proc/cmdline — what the running kernel was given.
  if grep -qE '(^|[[:space:]])(cryptdevice|rd\.luks\.name|rd\.luks\.uuid)=' /proc/cmdline 2>/dev/null; then
    raw=$(grep -oE 'cryptdevice=[^[:space:]"]+:root|rd\.luks\.name=[^[:space:]"]+=root|rd\.luks\.uuid=[^[:space:]"]+' /proc/cmdline | head -1)
  fi

  # b) Bootloader config — scanned even if /proc/cmdline matched, so we
  # can pick up an updated cmdline that hasn't been booted yet.
  if [[ -z $raw ]]; then
    local f
    for f in /etc/kernel/cmdline /etc/cmdline.d/*.conf \
             /boot/loader/entries/*.conf /efi/loader/entries/*.conf \
             /boot/limine.conf /boot/limine/limine.conf \
             /etc/default/grub; do
      [[ -f $f ]] || continue
      raw=$(sudo grep -oE 'cryptdevice=[^[:space:]"]+:root|rd\.luks\.name=[^[:space:]"]+=root|rd\.luks\.uuid=[^[:space:]"]+' "$f" 2>/dev/null | head -1)
      [[ -n $raw ]] && break
    done
  fi

  # c) /etc/crypttab — fallback for setups where cmdline doesn't carry it.
  if [[ -z $raw && -f /etc/crypttab ]]; then
    local src
    src=$(awk '$1 !~ /^#/ && NF >= 2 { print $2; exit }' /etc/crypttab)
    if [[ -n $src ]]; then
      NIRIMAKI_LUKS_UUID=$(_pm_resolve_luks_uuid "$src" || true)
      [[ -n $NIRIMAKI_LUKS_UUID ]] && return 0
    fi
  fi

  [[ -n $raw ]] || return 1

  # rd.luks.name=<luks-uuid>=root — UUID is already the LUKS UUID.
  if [[ $raw == rd.luks.name=* ]]; then
    NIRIMAKI_LUKS_UUID="${raw#rd.luks.name=}"
    NIRIMAKI_LUKS_UUID="${NIRIMAKI_LUKS_UUID%=root}"
    return 0
  fi
  # rd.luks.uuid=<luks-uuid>
  if [[ $raw == rd.luks.uuid=* ]]; then
    NIRIMAKI_LUKS_UUID="${raw#rd.luks.uuid=}"
    return 0
  fi
  # cryptdevice=<source>:root — resolve source → device → LUKS UUID.
  if [[ $raw == cryptdevice=* ]]; then
    local src="${raw#cryptdevice=}"
    src="${src%:root}"
    NIRIMAKI_LUKS_UUID=$(_pm_resolve_luks_uuid "$src" || true)
    [[ -n $NIRIMAKI_LUKS_UUID ]] && return 0
  fi

  return 1
}

# 3. Rewrite the HOOKS line in /etc/mkinitcpio.conf.
#
# Idempotent — sed match-and-replace handles re-runs cleanly.
# Backs up first so a misparse is recoverable.
_pm_hooks_rewrite() {
  section "Plymouth: mkinitcpio HOOKS rewrite"
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
    # Match cryptdevice=<anything>:root — covers UUID=, PARTUUID=, LABEL=,
    # /dev/disk/by-*, raw /dev/...  paths. We always emit the LUKS volume
    # UUID (resolved upstream by _pm_resolve_luks_uuid), which is what
    # sd-encrypt's rd.luks.name= requires.
    if sudo grep -qE 'cryptdevice=[^[:space:]"]+:root' "$f"; then
      sudo cp -n "$f" "$f.nirimaki-bak"
      # root=/dev/mapper/root is typically already on the cmdline next
      # to cryptdevice= (encrypt hook needs it explicitly), so we don't
      # add it — that would duplicate the arg.
      sudo sed -i -E "s|cryptdevice=[^[:space:]\"]+:root|rd.luks.name=$NIRIMAKI_LUKS_UUID=root|g" "$f"
      ok "rewrote cmdline in $f (backup at $f.nirimaki-bak)"
      changed=1
    elif sudo grep -qE "rd.luks.name=$NIRIMAKI_LUKS_UUID=root" "$f"; then
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

# Ensure `quiet splash` is on the kernel cmdline — Plymouth shows
# nothing without them. Touches every bootloader cmdline file we
# recognise (systemd-boot, limine, mkinitcpio UKI presets). Skips
# files that already have both flags.
_pm_cmdline_quiet_splash() {
  section "Plymouth: ensure 'quiet splash' on kernel cmdline"
  local f changed=0
  for f in /etc/kernel/cmdline /etc/cmdline.d/*.conf \
           /boot/loader/entries/*.conf /efi/loader/entries/*.conf \
           /boot/limine.conf /boot/limine/limine.conf \
           /etc/default/grub; do
    [[ -f $f ]] || continue
    # Skip if both already present.
    if grep -qE '(^|[[:space:]])quiet([[:space:]]|$)' "$f" \
      && grep -qE '(^|[[:space:]])splash([[:space:]]|$)' "$f"; then
      ok "$f already has quiet+splash"
      continue
    fi
    sudo cp -n "$f" "$f.nirimaki-bak"
    # Append to the FIRST cmdline-bearing line. systemd-boot entries
    # have `options …`, limine has `cmdline: …`, /etc/kernel/cmdline
    # is the whole file, /etc/default/grub has GRUB_CMDLINE_LINUX=.
    if [[ $f == /etc/kernel/cmdline ]] || [[ $f == /etc/cmdline.d/* ]]; then
      grep -qE '(^|[[:space:]])quiet([[:space:]]|$)' "$f" || echo -n " quiet" | sudo tee -a "$f" >/dev/null
      grep -qE '(^|[[:space:]])splash([[:space:]]|$)' "$f" || echo -n " splash" | sudo tee -a "$f" >/dev/null
    elif [[ $f == /etc/default/grub ]]; then
      sudo sed -i -E '/^GRUB_CMDLINE_LINUX(_DEFAULT)?=/{
        /quiet/!s/="(.*)"$/="\1 quiet"/
        /splash/!s/="(.*)"$/="\1 splash"/
      }' "$f"
    else
      # systemd-boot `options …` or limine `cmdline: …`
      sudo sed -i -E '/^[[:space:]]*(options|cmdline:)[[:space:]]/{
        /quiet/!s/$/ quiet/
        /splash/!s/$/ splash/
      }' "$f"
    fi
    ok "added quiet+splash to $f (backup at $f.nirimaki-bak)"
    changed=1
  done
  if (( ! changed )); then
    warn "no recognised bootloader cmdline file found — Plymouth may not render"
  fi
}

# 5. UKI splash replacement — only when the preset references the
# stock Arch splash. systemd-boot non-UKI setups won't have this file,
# and ad-hoc setups may already use a custom splash.
_pm_uki_splash() {
  section "Plymouth: UKI splash replacement"
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
  run_quiet "plymouth-set-default-theme qs-minimal" -- sudo plymouth-set-default-theme qs-minimal
  run_quiet "mkinitcpio -P (rebuild initramfs)" -- sudo mkinitcpio -P

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
  _pm_cmdline_quiet_splash
  _pm_uki_splash
  _pm_finalise
}
