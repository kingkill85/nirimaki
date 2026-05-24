echo "Gaming responsiveness: ananicy-cpp (auto-niceing daemon)"
#
# Why: ananicy-cpp keeps interactive processes snappy by adjusting
# nice/ioclass/sched policy per-rule. The previous gaming-layer
# migration didn't pull it in — backfill for existing Steam users.
# On CachyOS the daemon already arrives via cachyos-settings (which
# also drops cachyos-ananicy-rules, ~300 curated rules in
# /etc/ananicy.d/), but the service may not be enabled. On vanilla
# Arch we install the daemon; its own minimal default rules apply,
# and users who want the broader rule set can install ananicy-rules
# from AUR separately.

if ! pacman -Qq steam >/dev/null 2>&1; then
  echo "  steam not installed — skipping ananicy-cpp backfill"
  exit 0
fi

if ! pacman -Qq ananicy-cpp >/dev/null 2>&1; then
  echo "  installing ananicy-cpp"
  sudo pacman -S --needed --noconfirm ananicy-cpp
else
  echo "  ananicy-cpp already installed"
fi

if ! systemctl is-enabled ananicy-cpp.service >/dev/null 2>&1; then
  echo "  enabling ananicy-cpp.service"
  sudo systemctl enable --now ananicy-cpp.service
else
  echo "  ananicy-cpp.service already enabled"
fi
