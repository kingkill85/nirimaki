# Install steps — canonical spec for `install.sh`

This is the **integration layer** between the per-phase work and a
future `install.sh` that takes a blank Arch box to a working
Nirimaki desktop. Phase docs (A–K) record what shipped + why per
feature; this doc records the global recipe.

When a phase changes the package list, the seed contract, or a manual
step, update **this file** as well as the phase doc.

---

## 0. Assumptions about the target host

- Arch Linux, base + base-devel + git already present.
- Wayland-capable hardware.
- niri 26.04+ available in `extra/` (required for the `~` include
  expansion this layout uses).
- `paru` (or another AUR helper) installed for AUR packages.
- A user account exists; install.sh runs as that user and prompts
  once for `sudo` (PAM auth).
- The Nirimaki repo is cloned somewhere stable (typical:
  `~/Projekte/kingkill85/nirimaki`) **OR** `install.sh` clones it
  to `~/.local/share/nirimaki/`.

---

## 1. Repo location

End-user install layout (post-install.sh):

```
~/.local/share/nirimaki/        ← the clone
  default/                       ← repo-owned, upgrade-tracked
    niri/{input,looknfeel,autostart,windows,bindings}.kdl
    bash/rc
  bin/                           ← all nirimaki-* helpers
  config/                        ← user-side seed templates
  install/                       ← THIS spec's helpers
  …
```

`install.sh` either clones the repo there itself or asks the user to
clone it there before running.

---

## 2. Packages

### 2a. `install/base.packages` (pacman, from `extra`/`core`/`multilib`)

Source of truth: `install/base.packages` in the repo. The list is
kept short — only items the user always gets without a menu. Run:

```bash
sudo pacman -S --needed --noconfirm $(grep -v '^[[:space:]]*\(#\|$\)' install/base.packages)
```

As of phase L (this consolidation):

- `mise` — version manager for the Install → Development menu's
  dev envs (ruby/node/go/python/dotnet/…)
- `opencode` — Anthropic-style AI coding assistant (one of the
  always-on standard tools)

### 2b. Compositor + shell + GUI baseline (pacman)

```bash
sudo pacman -S --needed \
  niri quickshell \
  swaybg swayidle \
  foot \
  wiremix bluetui impala \
  ddcutil wf-recorder cliphist wl-clipboard \
  pavucontrol blueman-manager \
  qt5ct qt6ct gnome-themes-extra yaru-icon-theme \
  fontconfig ttf-jetbrains-mono-nerd \
  plymouth \
  wtype
```

### 2c. Terminal toolkit (Phase H)

```bash
sudo pacman -S --needed \
  fish starship \
  eza bat fzf zoxide ripgrep fd git-delta \
  lazygit tealdeer sd ouch dust duf procs xh hyperfine tokei \
  tmux \
  yazi \
  neovim \
  jq
```

### 2d. AUR (paru)

```bash
paru -S --needed \
  pay-respects-bin
```

### 2e. Standard tools NOT in pacman/AUR — `install/bootstrap-extras.sh`

```bash
install/bootstrap-extras.sh
```

Idempotent. Installs:

- **claude-code** via Anthropic's official installer
  (`curl -fsSL https://claude.ai/install.sh | bash`).
- **pi** via the upstream installer at `https://pi.dev/install.sh`.

Both land binaries under `~/.local/bin/` (or claude's installer
default), no system-level state needed.

### 2f. Browsers (Phase I)

```bash
sudo pacman -S --needed chromium firefox
# Zen is AUR / external — left to the user.
```

After install:

```bash
# Chromium managed-policy dir — needed for live theme swap. Identical
# to Omarchy install/config/theme.sh.
sudo mkdir -p /etc/chromium/policies/managed
sudo chmod a+rw /etc/chromium/policies/managed

# Initial default browser — pick Zen if available, else Firefox.
xdg-settings set default-web-browser zen-browser.desktop \
  || xdg-settings set default-web-browser firefox.desktop
```

The chmod is the only privileged step at theme-swap runtime.
`nirimaki-theme-set` never sudoes; if the dir isn't writable, it
silently degrades to "no live chromium reload" (newly-spawned
chromium instances still pick up theming on launch).

---

## 3. fish as the login shell (Phase H1)

```bash
grep -qx /usr/bin/fish /etc/shells || echo /usr/bin/fish | sudo tee -a /etc/shells
chsh -s /usr/bin/fish
```

User has to log out + back in after `chsh`. bash stays as `/bin/sh`
and the script interpreter.

---

## 4. Config copy + symlink contract

This is the heart of the install. Two flavours per surface:

| Surface | Repo path | Live path | Strategy |
|---|---|---|---|
| niri defaults | `default/niri/` | `~/.local/share/nirimaki/default/niri/` | symlink (or already at that path if repo is cloned there) |
| niri user files | `config/niri/*.kdl` | `~/.config/niri/*.kdl` | **copy if missing** — user-owned |
| Quickshell | `config/quickshell/` | `~/.config/quickshell/` | dir-symlink (repo-owned) |
| foot | `config/foot/foot.ini` | `~/.config/foot/foot.ini` | **copy if missing** — user-owned |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | **copy if missing** — user-owned |
| fish init | `config/fish/conf.d/` | `~/.config/fish/conf.d/` | dir-symlink (repo-owned) |
| fish config | `config/fish/config.fish` | `~/.config/fish/config.fish` | **copy if missing** — user-owned |
| fish state | `config/fish/{completions,functions,themes,fish_plugins,fish_variables}` | matching `~/.config/fish/` | dir-symlink (managed by fisher) |
| nvim | `config/nvim/` | `~/.config/nvim/` | dir-symlink (LazyVim manages lock file) |
| theme templates | `config/theme/templates/` | `~/.config/theme/templates/` | dir-symlink (repo-owned) |
| theme themes | `config/theme/themes/` | `~/.config/theme/themes/` | dir-symlink (repo-owned) |
| bash defaults | `default/bash/rc` | `~/.local/share/nirimaki/default/bash/rc` | symlink (from #1 above) |
| nirimaki samples | `config/nirimaki/<dir>/*.sample` | `~/.config/nirimaki/<dir>/*.sample` | per-file symlink — `.sample` files are tracked, user-added active files coexist |
| Desktop launchers | `config/applications/*.desktop` | `~/.local/share/applications/*.desktop` | per-file symlink |
| Helpers | `bin/nirimaki*` | `~/.local/bin/nirimaki-*` | per-file symlink |

**Important: every "copy if missing" file is user-owned after the
first install — never overwrite on upgrade.** This is why install.sh
mirrors dev-link.sh's `seed_user_file` helper:

```bash
seed_user_file() {
  local src="$1" dest="$2"
  if [[ -e $dest || -L $dest ]]; then return; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}
```

A simple way to do this in install.sh: just shell out to `dev-link.sh`
itself. It already handles the whole contract and is idempotent.

---

## 5. `~/.bashrc`

Same source-line pattern as fish's conf.d → config.fish: Nirimaki
defaults load first via `default/bash/rc`, user's own `~/.bashrc`
content sits below the source line and wins via evaluation order.

`install.sh` prepends this block at the top of `~/.bashrc` (after
any existing non-interactive guard) **only if it isn't there yet**:

```bash
# Nirimaki — load shared bash defaults (starship, mise, $EDITOR).
# This must stay near the top so anything below in your ~/.bashrc
# runs AFTER and wins via bash's evaluation order.
[[ -f $HOME/.local/share/nirimaki/default/bash/rc ]] && \
  source "$HOME/.local/share/nirimaki/default/bash/rc"
```

`default/bash/rc` handles: PATH (~/.local/bin), starship init, mise
activate, `$EDITOR`/`$VISUAL` from `~/.config/nirimaki/editor`,
`BAT_THEME=nirimaki`. All guarded so missing tools don't break boot.

---

## 6. `~/.gitconfig` delta block

Per-machine; append (idempotently) if not present:

```ini
[core]
	pager = delta
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	line-numbers = true
	side-by-side = true
	syntax-theme = ansi
[merge]
	conflictstyle = zdiff3
```

---

## 7. fisher + fish plugins

`config/fish/fish_plugins` is fisher's source-of-truth file. After
fisher bootstrap, a single `fisher update` reads it and pulls every
listed plugin:

```bash
fish -c '
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  fisher install jorgebucaran/fisher
  fisher update
'
```

Plugins as of Phase H5: fisher / fzf.fish / autopair.fish / done /
sponge / puffer-fish. Repo's `config/fish/.gitignore` keeps the
fetched plugin files out of git while tracking our authored files
via an explicit whitelist.

---

## 8. LazyVim bootstrap

LazyVim/starter is vendored at `config/nvim/`. One-time headless
sync:

```bash
nvim --headless "+Lazy! sync" +qa
```

`lazy-lock.json` is gitignored so each user gets fresh plugins.

---

## 9. tldr cache

```bash
tldr --update
```

One-time ~2 MB download for the offline page cache.

---

## 10. Initial theme apply

```bash
nirimaki theme set tokyo-night
```

One call renders every `.tpl` → its destination (kitty.conf-equiv,
btop, starship.toml, lazygit, bat tmTheme, yazi, fish-colors,
niri-theme.kdl, qt-colors.conf, foot palette, ...), builds the bat
cache, sources fish-colors, IPCs Quickshell + niri + nvim sockets to
hot-reload.

---

## 11. Plymouth boot splash (Phase D9)

```bash
sudo install -d /usr/share/plymouth/themes/qs-minimal
sudo install -m 644 assets/plymouth/* /usr/share/plymouth/themes/qs-minimal/

sudo plymouth-set-default-theme qs-minimal
sudo mkinitcpio -P
```

Requires `mkinitcpio.conf` HOOKS already include `plymouth` after
`systemd` (Phase D7 step).

---

## 12. qt5ct / qt6ct color_scheme_path (deferred templating)

The one remaining hardcoded path in the install. `qt5ct.conf` /
`qt6ct.conf` reference `~/.config/theme/current/qt-colors.conf` via
their `color_scheme_path=` directive. **qt5ct/qt6ct don't expand
`~` or env vars in INI values**, so install.sh has to write the
target user's literal home:

```bash
mkdir -p "$HOME/.config/qt6ct" "$HOME/.config/qt5ct"

for qtc in "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"; do
  cat > "$qtc" <<EOF
[Appearance]
custom_palette=true
color_scheme_path=$HOME/.config/theme/current/qt-colors.conf
icon_theme=Yaru-blue
style=Fusion
EOF
done
```

`nirimaki-theme-set` later mutates only the `icon_theme=` line per
swap; the `color_scheme_path=` line stays the literal absolute path
written here.

---

## 13. Auto-start helpers (covered by `default/niri/autostart.kdl`)

Already wired in the niri defaults — install.sh doesn't need to do
anything extra. For reference, the autostart entries are:

- `quickshell` (the bar/shell)
- `$HOME/.local/bin/nirimaki-wallpaper-apply`
- `$HOME/.local/bin/nirimaki-feature-state` — seeds the install/remove
  menu's "is X installed?" cache at session start
- `$HOME/.local/bin/nirimaki-font-menu-refresh` — seeds the Style →
  Font menu fragment so it's populated at first open
- `swayidle` (lock + display power-off)
- `wl-paste --watch cliphist store` (clipboard history)

If install.sh decides to ship its own autostart on top, append to
`~/.config/niri/autostart.kdl` (user-owned, additive).

---

## 14. Verification checklist

```bash
# Login shell
getent passwd $USER | cut -d: -f7              # /usr/bin/fish

# Core CLI
for c in fish starship eza bat fzf zoxide rg fd delta lazygit tldr \
         pay-respects sd ouch dust duf procs xh hyperfine tokei \
         tmux yazi nvim jq mise opencode claude pi; do
  command -v $c >/dev/null && echo "ok $c" || echo "MISS $c"
done

# niri loads cleanly
niri validate -c ~/.config/niri/config.kdl

# Quickshell IPC alive
quickshell ipc call -- settings-menu ping

# Theme apply
nirimaki theme set gruvbox && nirimaki theme set tokyo-night

# Feature state populated
cat ~/.cache/nirimaki/state.json | python3 -m json.tool | head
```

---

## What's deferred to a later install.sh pass

- **SDDM theme + autologin** — Phase 2 of the user-overrides arc.
  Theme-tracking via polkit rule, autologin pre-seed, login screen
  consistency. Scoped, not built yet.
- **gh login**, **1Password CLI provisioning**, anything that needs
  network credentials — left to the user post-install.
- **Per-machine state** never shipped: `~/.local/share/fish/bookmarks`,
  `~/.config/quickshell/locale`, `~/.config/theme/current/theme.name`,
  `~/.config/nirimaki/{editor,font}`, `~/.bashrc.local` if used,
  user-installed webapps under `~/.cache/nirimaki-webapps/`.

---

## What this doc does NOT cover

- The PRIOR phases (A–K) have their own outcomes; install.sh has
  to replay those (Plymouth boot logo, theme switcher infra, the
  full Quickshell dialog set, etc.). When install.sh is written,
  **collapse the A–K phase outcomes into a single packaging
  script** rather than duplicating their docs.
