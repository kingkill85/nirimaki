# Nirimaki

An Omarchy-style desktop built on Arch Linux + [niri][niri] +
[Quickshell][qs]. Name = **niri + maki** (rolled sushi), parallel
to **Omarchy = omakase + Arch**.

[niri]: https://github.com/YaLTeR/niri
[qs]:   https://quickshell.outfoxxed.me/

## What's inside

- `config/niri/` — niri compositor config (`config.kdl`,
  `keybinds.kdl`). Lays out outputs, window rules, transparency,
  per-app opacity, screen-capture blocking for password managers.
- `config/quickshell/` — the entire shell: bar widgets,
  `DialogShell` (scrim + dialog two-surface pattern), Launcher,
  PowerMenu, all the pickers, lock screen, i18n.
- `config/theme/` — theme system. `themes/<name>/` contains
  `colors.toml` per theme; `templates/*.tpl` are per-app templates
  that `qs-theme-set` renders into `~/.config/theme/current/`.
- `bin/` — `qs-theme-set`, `qs-wallpaper-apply`, `qs-osd`, audio /
  brightness helpers. Installed into `~/.local/bin/`.
- `docs/phase-*.md` — incremental build log. Each phase document
  has an `### Outcome` section describing the actual end state.
- `assets/` — branding (ASCII logo source, coloured PNG variants,
  splash bitmap, plymouth assets).

## Live development

```bash
git clone https://github.com/kingkill85/nirimaki.git ~/Projekte/kingkill85/nirimaki
cd ~/Projekte/kingkill85/nirimaki
./dev-link.sh           # replaces ~/.config/{niri,quickshell,theme/{templates,themes}}
                        # + ~/.local/bin/qs-* with symlinks back to the repo
```

After `dev-link.sh`, edits in the repo immediately reach the live
session — `Edit` a QML file and quickshell hot-reloads, `Edit`
`config/niri/config.kdl` and niri picks it up.

`dev-link.sh` is idempotent and safe to re-run after pulling.

## Fresh install on blank Arch (planned)

`install.sh` will:
1. Install packages from `packages.txt` (pacman + AUR).
2. Copy `config/*` into `~/.config/`, `bin/*` into `~/.local/bin/`.
3. Enable the systemd units (swayidle, niri-session …).
4. Run `qs-theme-set default` to materialise the active theme.

Not implemented yet — see `docs/` for the manual phase-by-phase
build log in the meantime.

## License

MIT — see `LICENSE`.
