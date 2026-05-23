#!/bin/bash
# install/preflight.sh — sanity checks that must pass before install.sh
# starts touching the system.
#
# What we check (in order):
#   1. We're on Arch (or an Arch derivative — /etc/arch-release exists).
#   2. We're NOT running as root. install.sh has to know the target
#      user for chsh, ~/.config seeding, sudo prompts, etc. — running
#      it under sudo would leave files owned by root.
#   3. Network reachability — pacman/paru/fisher/lazyvim/tldr all need it.
#   4. niri 26.04+ available in extra/ (needed for the `~` include
#      expansion the user-side niri config relies on).
#   5. Dev-install collision at ~/.local/share/nirimaki/default.
#      Per user policy: just convert without confirm (the user-side
#      data we touch — symlinks/config seeds — is recoverable from
#      the repo, and the user explicitly asked for "just do it").
#
# This file is sourced; preflight() is the entrypoint.

# Source guard so install.sh re-sourcing doesn't redefine.
if [[ -n ${NIRIMAKI_PREFLIGHT_LOADED:-} ]]; then
  return 0
fi
NIRIMAKI_PREFLIGHT_LOADED=1

preflight() {
  section "Pre-flight"

  # 1. Arch check
  if [[ ! -f /etc/arch-release ]]; then
    die "Nirimaki targets Arch Linux. /etc/arch-release not found — refusing to install."
  fi
  ok "Arch Linux detected"

  # 2. Non-root check. EUID 0 = running under sudo or as root user.
  if [[ $EUID -eq 0 ]]; then
    die "Don't run install.sh as root. Run it as your user — sudo will be requested when needed."
  fi
  if [[ -z ${HOME:-} || $HOME == "/root" || $HOME == "/" ]]; then
    die "\$HOME points to '$HOME' — install.sh needs a regular user home."
  fi
  ok "Running as $USER (home: $HOME)"

  # 3. Network
  # Cheap reachability test: pacman's mirror status endpoint. Tolerates
  # captive portals badly on purpose — if this fails the install would
  # too, better to bail early.
  if ! curl -fsSL --max-time 10 https://archlinux.org/mirrorlist/ -o /dev/null; then
    die "Couldn't reach archlinux.org. Connect to the network and re-run."
  fi
  ok "Network reachable"

  # 3b. git — the preflight repo-clone below needs it, and the
  # archinstall "Minimal" profile doesn't ship it. One sudo prompt is
  # already coming from sudo_prime in install.sh; we ride that.
  if ! command -v git >/dev/null 2>&1; then
    info "git not installed — pulling it now"
    sudo pacman -Sy --noconfirm --needed git || die "couldn't install git — check pacman mirrors"
    ok "git installed"
  fi

  # 4. niri 26.04+ — we don't have niri yet on a blank box, so check
  # what pacman would install. Older builds can't expand `~` in the
  # include directive, which kills our config layout silently.
  local niri_ver
  niri_ver="$(pacman -Si niri 2>/dev/null | awk -F': *' '/^Version/ {print $2; exit}')"
  if [[ -z $niri_ver ]]; then
    warn "niri not in any enabled repo (extra/community). Enable extra/ before continuing."
  else
    # pacman -Si prints "Version: 26.04-1" (pkgver-pkgrel). Hand-rolled
    # `cut -d. -f2` parsed "04-1" and bash arithmetic evaluated it as
    # 04 minus 1 = 3 < 4 → false negative. Use pacman's vercmp instead.
    if (( $(vercmp "$niri_ver" 26.04) < 0 )); then
      warn "niri $niri_ver is older than 26.04 — the user-side config uses '~' in include= which needs 26.04+."
    else
      ok "niri $niri_ver available"
    fi
  fi

  # 5. Dev-install collision.
  # ~/.local/share/nirimaki/default is a symlink iff dev-link.sh has
  # run. Per user choice: convert (no backup, no confirm).
  local share="$HOME/.local/share/nirimaki"
  if [[ -L $share/default ]]; then
    local resolved
    resolved="$(readlink -f "$share/default" 2>/dev/null || true)"
    warn "Dev install detected at $share (symlink → $resolved)"
    warn "  Removing dev symlinks under ~/.local/share/nirimaki/ and cloning fresh."
    warn "  (Per your instruction: no backup. Commit/stash anything you care about in the dev repo first.)"

    # Only remove links + the share dir itself if it's purely the dev
    # scaffolding. If a real .git is there (end-user clone), we'd be
    # destroying their working copy — refuse instead.
    if [[ -d $share/.git ]]; then
      die "$share has its own .git — that's an end-user clone, not a dev symlink. Aborting to avoid data loss."
    fi
    rm -rf "$share"
    ok "removed $share"
  fi

  # End-user clone target: if it already exists with a .git, fine
  # (re-run / repair scenario). If it exists without .git AND without
  # dev symlinks, that's unexpected — bail.
  if [[ -d $share && ! -d $share/.git ]]; then
    die "$share exists but isn't a git checkout — refusing to overwrite. Inspect and remove manually."
  fi
  if [[ ! -d $share ]]; then
    info "Cloning Nirimaki repo to $share …"
    mkdir -p "$(dirname "$share")"
    git clone https://github.com/kingkill85/nirimaki.git "$share"
    ok "cloned $share"
    # If we were invoked from outside the canonical path, point future
    # steps at the new clone — REPO_DIR was set in helpers.sh from
    # this file's location. Re-set if our location differs.
    if [[ "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" != "$share" ]]; then
      REPO_DIR="$share"
      export REPO_DIR
      info "REPO_DIR updated to $REPO_DIR"
    fi
  else
    ok "Repo present at $share"
  fi

  # 6. Mark all currently-shipped migrations as already-applied.
  # install.sh does the work natively (better than migrations would —
  # full sudo orchestration, dependency awareness). Migrations only
  # need to run for changes added AFTER this install — those will have
  # later timestamps and no marker yet. Mirrors omarchy's
  # install/preflight/migrations.sh.
  if [[ -d $REPO_DIR/migrations ]]; then
    local migration_state="$HOME/.local/state/nirimaki/migrations"
    mkdir -p "$migration_state"
    shopt -s nullglob
    for file in "$REPO_DIR"/migrations/*.sh; do
      touch "$migration_state/$(basename "$file")"
    done
    shopt -u nullglob
    ok "marked $(ls "$migration_state" 2>/dev/null | wc -l) migration(s) as applied"
  fi
}
