# Claude project notes — Nirimaki

> Notes for any future Claude (or claude-code session) that picks up
> work on this repo. Keeps you from re-deriving things that have
> already been decided.

## What this repo is

**Nirimaki** = an Omarchy-style desktop for Arch Linux, but running
on **niri** (scrolling-column Wayland compositor) instead of
Hyprland. Wordplay on niri + *maki* (rolled sushi), parallel to
Omarchy = omakase + Arch.

Same opinionated baseline (themes, dialogs, lock screen, pickers,
keybinds), different compositor + shell stack:
- Compositor: [niri](https://github.com/YaLTeR/niri) 26.04+
- Shell:      [Quickshell](https://quickshell.outfoxxed.me/) 0.3

## Live development model — important

The repo's `dev-link.sh` replaces several live paths with **symlinks
back into this repo**, so editing in the repo == editing the live
session:

```
~/.config/niri/                  -> config/niri/
~/.config/quickshell/            -> config/quickshell/
~/.config/theme/templates/       -> config/theme/templates/
~/.config/theme/themes/          -> config/theme/themes/
~/.local/bin/qs-<each>           -> bin/qs-<each>     (one symlink per helper)
```

So when you edit `config/quickshell/Bar.qml` in this repo, you're
also editing `~/.config/quickshell/Bar.qml`.

### Reloading after edits

- **niri**: auto-reloads on config save. No manual step.
- **Quickshell**: needs a restart. Always launch it with the
  *user-facing symlinked path*:

  ```bash
  quickshell list --all 2>&1 | grep "Process ID" | awk '{print $3}' | xargs -r kill
  quickshell -p ~/.config/quickshell/shell.qml &
  ```

  **Do not** `cd` into `~/.config/quickshell/` and run `quickshell -p
  shell.qml` — quickshell resolves the real path and the Shell ID
  stops matching `quickshell ipc call` lookups (which key off the
  literal `~/.config/...` path the user passed).

## Repo layout

```
config/niri/        config.kdl + keybinds.kdl
config/quickshell/  Bar.qml, DialogShell.qml, the 9 dialogs,
                    services (NiriService, NotificationService,
                    UpdatesService, PopupBus, I18n), Theme.qml,
                    /lock (lock screen shell), /i18n (en/de json)
config/theme/
  templates/        kitty.conf.tpl, btop.theme.tpl,
                    niri-theme.kdl.tpl, qt-colors.conf.tpl
  themes/<name>/    colors.toml, backgrounds/, preview.png, …
bin/                qs-theme-set, qs-theme-list,
                    qs-wallpaper-apply, qs-osd, qs-screenrecord,
                    qs-audio-output-volume, qs-audio-input-mute,
                    qs-brightness-display
docs/phase-*.md     A-G phase logs — each has `### Outcome`
                    describing what actually shipped
assets/             logo (ASCII + PNG variants), splash.bmp,
                    plymouth/
```

## ~/.config/theme/current/ is NOT in scope

It's a regular directory that `qs-theme-set` rewrites in place
(`cp -f`) when switching themes — preserves inotify watches that
Quickshell's `FileView` relies on. Don't symlink it, don't track
it. The repo only owns `templates/` and `themes/` (the sources).

## Gotchas worth knowing

1. **niri's PATH excludes `~/.local/bin/`.** Plain `spawn "..."` calls
   in `keybinds.kdl` need absolute paths to the `qs-*` helpers.
   `spawn-sh "..."` goes through a shell so `$HOME` expands there.
   The plain-spawn paths in `keybinds.kdl` still hard-code
   `/home/michael/` — `install.sh` will need to template these.

2. **Quickshell platform menus** (`QsMenuAnchor`, SNI tray menus)
   need `//@ pragma UseQApplication` at the top of `shell.qml`.

3. **AMD GPU + niri transparency**: opaque RGB framebuffers ignore
   niri's opacity multiplier. Force RGBA buffers from the client —
   e.g. kitty needs `background_opacity 0.99` in `kitty.conf`.
   Tracked as niri#2346.

4. **niri `include` directive** supports `~` since 26.04 only —
   any older niri build will choke on the `~/.config/...` includes.

5. **Quickshell IPC handler return types**: `function foo(): void` for
   fire-and-forget, `function foo(): string` if you want to return
   "ok" / errors. Mixing them up breaks the call from `quickshell ipc
   call`.

## Conventions

- **Omarchy parity is the design lead** when in doubt. Check
  upstream at `basecamp/omarchy` (GitHub) for hyprland config under
  `default/hypr/` and corresponding patterns. Port them; don't
  redesign.
- **Phase docs in `docs/phase-*.md`** are the source of truth for
  "what shipped and why". Update the Outcome section when you change
  something that contradicts the original plan.
- **Comments**: WHY, not WHAT. The code already says what it does.
- **Don't reformat untouched indentation** when editing — leaves
  noise in diffs.

## Git

- **No `git config --global` on this machine.** For commits, pass
  identity inline:
  ```bash
  GIT_AUTHOR_NAME="kingkill85" GIT_AUTHOR_EMAIL="michaelkusche@live.de" \
  GIT_COMMITTER_NAME="kingkill85" GIT_COMMITTER_EMAIL="michaelkusche@live.de" \
  git commit -m "..."
  ```
- Remote: `https://github.com/kingkill85/nirimaki.git`, branch `main`.
- Co-author trailer for AI work:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

## Common ops

| Task | Command |
|---|---|
| Validate niri config | `niri validate -c ~/.config/niri/config.kdl` |
| Switch theme | `qs-theme-set <name>` |
| List themes | `qs-theme-list` |
| Restart Quickshell | see *Live development model* above |
| Toggle a dialog | `quickshell ipc call <target> toggle` |
| Re-render logo PNGs from ASCII | `scripts/ascii2png.sh` |

## What's deferred

- **`install.sh` + `packages.txt`**: blank-Arch → Nirimaki. Has to
  template the `/home/michael/` paths in `keybinds.kdl` to the
  target user's `$HOME` at install time. Copy (not symlink) so a
  later `git pull` doesn't clobber a user's tweaks.
- **Phase H — terminal stuff**: scope TBD; user flagged it as the
  next phase at the close of the previous session.

## What NOT to do

- Don't run `git config --global` (see above).
- Don't add `~/.local/bin/` symlinks for `qs-*` to system-wide
  paths — they need to live in the user's `~/.local/bin/`.
- Don't reformat untouched code when making targeted edits.
- Don't write planning docs / analysis files unless asked. Update
  phase docs only when behaviour actually changes.
- Don't symlink `~/.config/theme/current/` — see above.
