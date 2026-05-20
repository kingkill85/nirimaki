# Install steps — source of truth for a future `install.sh`

A blow-by-blow record of what gets installed on a fresh Arch box to
reach the current Nirimaki state, ordered so a script can replay it.
The previous phases (A–G) describe individual feature work; this doc
is the **integration layer** for a future `install.sh`.

This file should be updated whenever a phase adds a new package, a
new external tool, or a new manual step the installer needs to
replay.

## 0. Assumptions about the target host

- Arch Linux, base + base-devel + git already present.
- Wayland-capable: niri 26.04+ (`extra/`).
- An AUR helper available (`paru` is what we use here; `yay` works
  too).
- User account exists; commands run as that user with `sudo` for
  pacman / chsh / `/etc/shells` edits.
- The Nirimaki repo is cloned somewhere stable (typical:
  `~/Projekte/kingkill85/nirimaki`).

## 1. Packages

Two pacman calls + one AUR call cover the whole stack.

### 1a. Compositor + shell + GUI baseline

```bash
sudo pacman -S \
  niri quickshell \
  swaybg swayidle \
  kitty \
  wiremix bluetui impala \
  ddcutil wf-recorder cliphist \
  pavucontrol blueman-manager \
  qt5ct qt6ct gnome-themes-extra \
  yaru-icon-theme \
  fontconfig ttf-jetbrains-mono-nerd \
  plymouth
```

(Some of these are already covered by phases A–G; listed here for
the install.sh which has to handle a blank machine.)

### 1b. Terminal toolkit (Phase H)

```bash
sudo pacman -S \
  fish starship \
  eza bat fzf zoxide ripgrep fd git-delta \
  lazygit tealdeer sd ouch dust duf procs xh hyperfine tokei \
  tmux \
  yazi \
  neovim \
  jq
```

### 1c. AUR

```bash
paru -S pay-respects-bin    # pre-built binary; option 1 is a Rust source build that's slower
```

## 2. fish as login shell (Phase H1)

```bash
# Add fish to /etc/shells if it isn't there (Arch's fish package usually adds it,
# but not always — be defensive).
grep -qx /usr/bin/fish /etc/shells || echo /usr/bin/fish | sudo tee -a /etc/shells

# Switch the user's interactive shell. bash stays as /bin/sh and script interpreter.
chsh -s /usr/bin/fish
```

User has to log out + back in after `chsh` (or open a fresh kitty
once `shell /usr/bin/fish` is in `kitty.conf`, which the dev-link
already provides).

## 3. Link repo configs into ~/.config/

```bash
cd /path/to/nirimaki
./dev-link.sh
```

Symlinks created:
- `~/.config/niri/`            → `repo/config/niri/`
- `~/.config/quickshell/`      → `repo/config/quickshell/`
- `~/.config/fish/`            → `repo/config/fish/`
- `~/.config/kitty/`           → `repo/config/kitty/`
- `~/.config/tmux/`            → `repo/config/tmux/`
- `~/.config/nvim/`            → `repo/config/nvim/`
- `~/.config/theme/templates/` → `repo/config/theme/templates/`
- `~/.config/theme/themes/`    → `repo/config/theme/themes/`
- `~/.local/bin/qs-<each>`     → `repo/bin/qs-<each>`

`install.sh` (deferred) will **copy** instead of symlink so a
later `git pull` doesn't clobber user tweaks, and templatize the
`/home/michael/` paths in `keybinds.kdl`.

## 4. ~/.bashrc additions

`~/.bashrc` is NOT symlinked (it's per-machine). Append the
Nirimaki block manually or via install.sh:

```bash
# --- Nirimaki ---------------------------------------------------------
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init bash --cmd cd)"

if command -v fzf >/dev/null 2>&1; then
    [[ -r /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash
    [[ -r /usr/share/fzf/completion.bash    ]] && . /usr/share/fzf/completion.bash
fi

if command -v bat >/dev/null 2>&1; then
    export PAGER=bat
    export MANPAGER='sh -c "col -bx | bat -l man -p"'
    export MANROFFOPT=-c
    export BAT_THEME=nirimaki
fi

command -v pay-respects >/dev/null 2>&1 && eval "$(pay-respects bash --alias)"
```

## 5. ~/.gitconfig delta block

Same idea — per-machine, append the block:

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

## 6. fisher + fish plugins

The fisher plugin list is committed at
`config/fish/fish_plugins`. fisher reads that file as its source of
truth, so:

```bash
fish -c '
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  fisher install jorgebucaran/fisher
  fisher update
'
```

The `fisher update` step is what reads the committed fish_plugins
and pulls every listed plugin. As of Phase H5:

```
jorgebucaran/fisher
patrickf1/fzf.fish
jorgebucaran/autopair.fish
franciscolourenco/done
meaningful-ooo/sponge
nickeb96/puffer-fish
```

Plugin files land in `~/.config/fish/{functions,completions,conf.d}/`
(actually in `repo/config/fish/...` via the symlink). The repo's
`config/fish/.gitignore` keeps the fetched plugin files out of git
while tracking our authored files explicitly.

## 7. LazyVim bootstrap

LazyVim/starter is vendored into `config/nvim/` already. The
plugin install is a one-time headless step:

```bash
nvim --headless "+Lazy! sync" +qa
```

Installs ~50 plugins including every colorscheme plugin Nirimaki's
themes reference. Subsequent installs reuse the same plugin set;
`lazy-lock.json` is gitignored so each user gets the latest at
install time.

## 8. tldr cache

```bash
tldr --update
```

One-time, ~2 MB download. Builds the offline page cache used by
the `tldr` / `help` fish abbreviation.

## 9. Initial theme apply

The Nirimaki theme system (Phase D + H9) runs from `qs-theme-set`.
A fresh install ships `last-horizon` as the bundled default —
trigger one swap so all template outputs are rendered:

```bash
qs-theme-set last-horizon       # or any theme from `qs-theme-list`
```

That single call:

- copies the theme files into `~/.config/theme/current/`
- renders every `.tpl` in `config/theme/templates/` → its
  destination (kitty.conf in current/, btop theme in
  `~/.config/btop/themes/qs.theme`, starship.toml in
  `~/.config/starship.toml`, lazygit config in
  `~/.config/lazygit/config.yml`, bat tmTheme in
  `~/.config/bat/themes/nirimaki.tmTheme`, yazi theme.toml in
  `~/.config/yazi/theme.toml`, fish colors universal-var script
  in `~/.config/theme/current/fish-colors.fish`, niri-theme.kdl,
  qt-colors.conf, …)
- runs `bat cache --build` so the new tmTheme is picked up
- sources `fish-colors.fish` (sets `set -U` universals →
  propagates to all running fish instances)
- IPCs Quickshell, niri, and every running nvim socket to
  hot-reload themes

## 10. Plymouth boot splash

```bash
# Copy the qs-minimal theme into Plymouth's theme dir.
sudo install -d /usr/share/plymouth/themes/qs-minimal
sudo install -m 644 assets/plymouth/* /usr/share/plymouth/themes/qs-minimal/

# Activate + bake into the UKI / initramfs.
sudo plymouth-set-default-theme qs-minimal
sudo mkinitcpio -P
```

Requires `mkinitcpio.conf` HOOKS already include `plymouth` after
`systemd` (set up in Phase D7).

## 11. Quake terminal first-run prep (optional)

The quake terminal launches into a persistent `tmux new-session -A
-s quake`. Nothing to install ahead of time — `tmux` (step 1b)
plus the `qs-quake-toggle` script (symlinked via step 3) are
enough. First `Mod+grave` press creates the session.

## 12. Verification checklist

```bash
# Login shell
getent passwd $USER | cut -d: -f7              # /usr/bin/fish

# Core CLI
for c in fish starship eza bat fzf zoxide rg fd delta lazygit tldr \
         pay-respects sd ouch dust duf procs xh hyperfine tokei \
         tmux yazi nvim jq; do
  command -v $c >/dev/null && echo "ok $c" || echo "MISS $c"
done

# Fish loaded right
fish -c 'echo abbrs=(abbr -l | count); echo functions=(functions | tr "," "\n" | grep -E "^(t|n|ff|eff|oc|cc|io|ic|ioc|bm|tdl)$" | count)'

# Themes propagate
qs-theme-set tokyo-night && qs-theme-set last-horizon
```

## What this doc does NOT cover

- The PRIOR phases (A–G) have their own outcomes; install.sh
  also has to replay those (Plymouth boot logo, Phase D theme
  switcher infrastructure, Quickshell dialog set, etc.). When
  install.sh is written, **collapse the A–G phase outcomes into a
  single packaging script** rather than duplicating their docs.
- Personal data: `~/.local/share/fish/bookmarks`, `~/.config/quickshell/locale`,
  and the active theme name in `~/.config/theme/current/theme.name`
  are per-user state, NOT shipped.
