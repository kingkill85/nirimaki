<div align="center">

<img src="assets/logo-amber.png" alt="Nirimaki" width="640">

**Niri + Maki.** An Omarchy-style desktop for Arch Linux, built on [niri] and [Quickshell].

![License](https://img.shields.io/badge/license-MIT-e0af68?style=flat-square)
![niri](https://img.shields.io/badge/niri-26.04+-e0af68?style=flat-square)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3-e0af68?style=flat-square)
![Status](https://img.shields.io/badge/status-self--hosting-e0af68?style=flat-square)

</div>

[niri]:      https://github.com/YaLTeR/niri
[Quickshell]: https://quickshell.outfoxxed.me/

---

## What it is

[Omarchy] is **omakase** (chef's choice) + **Arch** — a curated, opinionated
Arch desktop on top of Hyprland. Nirimaki is the same idea, retold for niri's
scrolling-column world: **niri + maki**, the rolled sushi answer to Omarchy's
plate. Same opinionated baseline (themes, dialogs, lock screen, picker
overlays, sane keybinds), different compositor underneath.

[Omarchy]: https://omarchy.org

It's a single repo you can drop on a fresh Arch install and end up with a
working, themed, multi-monitor desktop — without hand-stitching ten dotfile
sources together first.

---

## What you get

- **Compositor**: niri 26.04+ tuned for scrolling-column workflow,
  variable-refresh-rate outputs, German keymap, focus-follows-mouse.
- **Shell**: Quickshell. Top bar with workspaces, active-window title,
  audio, network, bluetooth, weather, system stats, calendar, tray,
  updates. Notification stack. OSD bezel for volume / brightness.
- **Dialog overlays** (Omarchy walker-style, all behind one
  [`DialogShell`](config/quickshell/DialogShell.qml) component): app
  launcher, power menu, theme picker, background picker, language
  picker, clipboard history, emoji picker, settings drilldown,
  keybind cheat-sheet.
- **22 themes** under `config/theme/themes/` — imported from Omarchy
  plus custom additions (`catppuccin`, `gruvbox`, `tokyo-night`,
  `nord`, `rose-pine`, `kanagawa`, `everforest`, `solitude`,
  `hackerman`, `retro-82`, …). One `qs-theme-set <name>` re-skins
  niri / Quickshell / kitty / btop / Qt apps atomically.
- **Wallpaper per theme**: each theme ships its own backgrounds;
  swap follows the theme.
- **Lock screen**: PAM-backed, i18n, wallpaper-aware backdrop.
- **i18n**: `en` + `de` translations, runtime locale switcher via the
  Language picker.
- **Transparency** dialed to Omarchy parity (per-app opacity rules,
  always-opaque media tools, screen-capture blocking on password
  managers).
- **Branded boot**: UKI splash + Plymouth assets in `assets/`.
- **Terminal stack**: fish (chsh'd) + starship + eza/bat/fzf/zoxide/
  ripgrep/fd/delta/lazygit/tmux/yazi/nvim (LazyVim). Quake terminal
  on `Mod+grave`. Theme swap re-skins bat, delta, fish syntax, yazi,
  lazygit, starship, kitty, tmux, and every running nvim instance
  live.

---

## Quick start (live dev mode)

```bash
git clone https://github.com/kingkill85/nirimaki.git ~/Projekte/kingkill85/nirimaki
cd ~/Projekte/kingkill85/nirimaki
./dev-link.sh
```

`dev-link.sh` replaces

```
~/.config/niri/                 →  this repo's config/niri/
~/.config/quickshell/           →                config/quickshell/
~/.config/fish/                 →                config/fish/
~/.config/kitty/                →                config/kitty/
~/.config/tmux/                 →                config/tmux/
~/.config/nvim/                 →                config/nvim/
~/.config/theme/templates/      →                config/theme/templates/
~/.config/theme/themes/         →                config/theme/themes/
~/.local/bin/qs-*               →                bin/qs-*
```

with symlinks back into the repo. Anything you already had at those
paths is moved to `<path>.pre-link` first as a backup. Idempotent;
re-runnable after `git pull`.

After linking, edit any file in the repo and it's live: niri
auto-reloads, Quickshell needs a quick:

```bash
quickshell list --all 2>&1 | grep "Process ID" | awk '{print $3}' | xargs -r kill
quickshell -p ~/.config/quickshell/shell.qml &
```

---

## Fresh-install on blank Arch (planned, not yet shipped)

The end goal — `./install.sh` on a barebones Arch install gives you a
themed, working Nirimaki desktop in one go:

1. `pacman` + AUR install from `packages.txt`.
2. Copy (not symlink) `config/*` → `~/.config/`, `bin/*` → `~/.local/bin/`.
3. Template `keybinds.kdl` spawn paths to the user's `$HOME`.
4. Enable systemd units (`swayidle`, `niri-session.target`, …).
5. `qs-theme-set default` → materialise the active theme.

The canonical install sequence is recorded in
[`docs/install-steps.md`](docs/install-steps.md). Until `install.sh`
ships, the manual install path is documented phase-by-phase under
[`docs/`](docs/) — start with
[`phase-a-foundations.md`](docs/phase-a-foundations.md).

---

## Repo layout

```
config/
  niri/         compositor config (config.kdl, keybinds.kdl)
  quickshell/   bar, DialogShell, dialogs, lock screen, i18n,
                services (Niri/Notification/Updates/PopupBus)
  fish/         config.fish + conf.d/ + functions/ (bm, tdl, …)
  kitty/        kitty.conf (font, padding, tab bar, IPC)
  tmux/         tmux.conf (Omarchy port — C-Space prefix, vi-mode)
  nvim/         LazyVim starter + Nirimaki theme hot-reload glue
  theme/
    templates/  per-app .tpl rendered by qs-theme-set
    themes/    22 themes (colors.toml + backgrounds + previews)
bin/            qs-theme-set, qs-quake-toggle, qs-wallpaper-apply,
                qs-osd, audio + brightness + screenrecord helpers
docs/           phase-a-foundations.md … phase-h-terminal.md
                + install-steps.md — the actual build log
assets/         logo (ASCII source + 11 coloured PNG variants),
                splash.bmp, plymouth/
scripts/        ascii2png.sh (logo rendering pipeline)
dev-link.sh     ↑ described above
```

---

## Docs

Each phase under [`docs/`](docs/) has an `### Outcome` section
describing the actual end state — not the original plan, but what
shipped. Read those first if you want to know **why** something is
the way it is.

| Phase | What |
|------:|------|
| A | Foundations — niri install, kdl basics, outputs |
| B | Shell — Quickshell bar, widgets, services |
| C | Polish — popups, animations, hotkey overlay |
| D | Theming — palette generator, templates pipeline, Plymouth + UKI branding |
| E | Consistency — Omarchy themes import, blur, transparency, single-popup bus |
| F | i18n + keybinds — I18n singleton, `keybinds.kdl`, KeybindSheet, lock-screen i18n |
| G | Settings dialogs — drilldown, pickers, runtime locale switcher |
| H | Terminal — fish + starship + modern CLI toolkit + tmux + LazyVim, all theme-aware |

`install.sh` is the remaining big piece.

---

## License

MIT — see [`LICENSE`](LICENSE).

<div align="center">

<img src="assets/logo-palette.png" alt="Nirimaki palette variants" width="640">

*Eleven recoloured logo variants ship in `assets/`. Pick your accent.*

</div>
