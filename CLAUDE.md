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
~/.local/share/nirimaki/default/ -> default/                  (upgrade-tracked
                                                              niri defaults)
~/.config/niri/                  COPIED from config/niri/    (USER-OWNED;
                                                              seeded once, never
                                                              overwritten)
~/.config/foot/foot.ini          COPIED from config/foot/foot.ini (user-owned;
                                                              theme tracks via
                                                              internal include=)
~/.config/tmux/tmux.conf         COPIED from config/tmux/tmux.conf (user-owned)
~/.config/quickshell/            -> config/quickshell/
~/.config/fish/config.fish       COPIED from config/fish/config.fish (user-owned)
~/.config/fish/{conf.d,functions,…} -> config/fish/{…}
~/.config/theme/templates/       -> config/theme/templates/
~/.config/theme/themes/          -> config/theme/themes/
~/.local/bin/nirimaki-<each>     -> bin/nirimaki-<each>      (one symlink per helper)
```

So when you edit `config/quickshell/Bar.qml` in this repo, you're
also editing `~/.config/quickshell/Bar.qml`. **But:** the niri files
under `~/.config/niri/*.kdl` are COPIES of the seed files in
`config/niri/`, not symlinks — they're user state once seeded, so
edits there do NOT write back to the repo. Edit `default/niri/*.kdl`
instead to change the upgrade-tracked defaults.

### The niri layout — defaults vs user files

Two camps, Omarchy-style:

- **`default/niri/*.kdl`** in this repo → reachable at
  `~/.local/share/nirimaki/default/niri/` via a dir-symlink. Upgrade-
  tracked, owned by Nirimaki. Five files: `input.kdl`, `looknfeel.kdl`,
  `autostart.kdl`, `windows.kdl`, `bindings.kdl`.
- **`~/.config/niri/*.kdl`** → real files seeded from `config/niri/`
  once, never overwritten. Six files: `config.kdl` (the entry-point
  that `include`s the defaults + the rest of these), `monitors.kdl`,
  `input.kdl`, `windows.kdl`, `bindings.kdl`, `autostart.kdl`. The
  entry-point loads defaults first, then user files — niri does
  last-wins for keyed nodes (output, environment, individual binds)
  so user files override defaults.

niri has **no native unbind**. To disable one of the default binds,
drop the key into `~/.config/niri/bindings.kdl` rebound to
`spawn-sh "true"` — the key is consumed but does nothing.

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
default/niri/       Upgrade-tracked niri defaults (input, looknfeel,
                    autostart, windows, bindings). Symlinked into
                    ~/.local/share/nirimaki/default/niri/ by dev-link.sh.
default/sddm/       Upgrade-tracked SDDM theme (`nirimaki/Main.qml`
                    + theme.conf + metadata.desktop). Copied to
                    /usr/share/sddm/themes/nirimaki/ by
                    install/login/sddm.sh; runtime state lives in
                    a state/ subdir chowned to the user, refreshed
                    by nirimaki-sddm-sync on every theme change.
config/niri/        User-side seeds — copied (not symlinked) to
                    ~/.config/niri/ on first run. config.kdl is the
                    entry-point; monitors.kdl + the four override files
                    ship as comment-only stubs.
config/quickshell/  Bar.qml, DialogShell.qml, the 9 dialogs,
                    services (NiriService, NotificationService,
                    UpdatesService, PopupBus, I18n), Theme.qml,
                    /lock (lock screen shell), /i18n (en/de json)
config/theme/
  templates/        kitty.conf.tpl, btop.theme.tpl,
                    niri-theme.kdl.tpl, qt-colors.conf.tpl
  themes/<name>/    colors.toml, backgrounds/, preview.png, …
bin/                nirimaki-theme-set, nirimaki-theme-list,
                    nirimaki-wallpaper-apply, nirimaki-osd, nirimaki-screenrecord,
                    nirimaki-audio-output-volume, nirimaki-audio-input-mute,
                    nirimaki-brightness-display
docs/phase-*.md     A-G phase logs — each has `### Outcome`
                    describing what actually shipped
assets/             logo (ASCII + PNG variants), splash.bmp,
                    plymouth/
```

## ~/.config/theme/current/ is NOT in scope

It's a regular directory that `nirimaki-theme-set` rewrites in place
(`cp -f`) when switching themes — preserves inotify watches that
Quickshell's `FileView` relies on. Don't symlink it, don't track
it. The repo only owns `templates/` and `themes/` (the sources).

## Gotchas worth knowing

1. **niri's PATH excludes `~/.local/bin/`.** Plain `spawn "..."` calls
   in `default/niri/bindings.kdl` can't find the `nirimaki-*` helpers
   by bare name. Use `spawn-sh "$HOME/.local/bin/nirimaki-foo"` — the
   shell expands `$HOME` per-user at runtime, so no install-time
   templating is needed. (Same trick for the included lock-screen path:
   `spawn-sh "quickshell -p $HOME/.config/quickshell/lock/shell.qml"`.)

   Niri **has no native unbind** ([wiki](https://github.com/niri-wm/niri/wiki/Configuration:-Key-Bindings) —
   niri loads no defaults of its own, so "unbinding" only ever means
   removing one of our shipped binds). The user-file workaround:
   rebind the key to `spawn-sh "true"` — key is consumed, action no-ops.
   `hotkey-overlay-title=null` is also legal and hides a bind from the
   Mod+Shift+/ overlay, but does NOT disable it.

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

## Migrations — picking up changes on existing installs

`install.sh` sets up a fresh box. But once a user is running Nirimaki,
changes to **system-owned** files (Plymouth theme at `/usr/share/
plymouth/themes/qs-minimal/`, SDDM theme at `/usr/share/sddm/themes/
nirimaki/`, `/etc/mkinitcpio.conf` HOOKS, kernel cmdline, system
services…) **aren't picked up by `git pull` alone** — those files
were COPIED, not symlinked.

The pattern (mirrors `basecamp/omarchy`):

- Drop a one-off script at `migrations/<unix-timestamp>.sh` alongside
  the change that requires it. Filename is `$(date +%s).sh`.
- `bin/nirimaki-migrate` loops through them in filename order, runs
  every unmarked one, and writes a state marker at
  `~/.local/state/nirimaki/migrations/<filename>` so it never runs
  twice. Failed migrations can be skipped → tracked under `.../skipped/`.
- `bin/nirimaki-update` calls `nirimaki-migrate` between `git pull`
  and `paru -Syu`, so every user picks up the change on their next
  update.

**When to add a migration:** any commit that needs an *existing
install* to do something `git pull` can't do for them. Examples:

| Change | Migration body |
|---|---|
| Plymouth asset edit | re-copy `assets/plymouth/*` → `/usr/share/plymouth/themes/qs-minimal/`, run `sudo mkinitcpio -P` |
| SDDM theme edit | re-copy `default/sddm/nirimaki/*` → `/usr/share/sddm/themes/nirimaki/` |
| New package | `paru -S --needed <pkg>` (or `pacman_install`) |
| New systemd enable | `sudo systemctl enable --now <svc>` |
| Kernel cmdline addition | sed the bootloader cmdline file + `mkinitcpio -P` if UKIs |

**Conventions inside a migration:**
- Print one banner line so the update log is scannable: `echo "Re-sync Plymouth …"`
- Idempotent — assume it may run on a half-complete state.
- Use `$NIRIMAKI_REPO` for repo-relative paths (exported by `nirimaki-update`, falls back to `~/.local/share/nirimaki` in `nirimaki-migrate` itself).
- `set -e` is opt-in (not enforced by the runner).

**Fresh installs:** migrations also run on the very first
`nirimaki-update` after install.sh. Since they're idempotent, that's
fine — but design them so re-doing what install.sh already did is
cheap.

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
| Validate niri config            | `niri validate -c ~/.config/niri/config.kdl` |
| Switch theme                    | `nirimaki theme set <name>`                  |
| List themes                     | `nirimaki theme list`                        |
| Install a webapp                | `nirimaki webapp install`                    |
| Change default browser          | `nirimaki browser default <zen\|firefox\|chromium>` |
| List all commands               | `nirimaki help`                              |
| Restart Quickshell              | see *Live development model* above           |
| Toggle a dialog                 | `quickshell ipc call <target> toggle`        |
| Re-render logo PNGs from ASCII  | `scripts/ascii2png.sh`                       |

The bare names (`nirimaki-theme-set`, `nirimaki-webapp-install`, …)
stay directly executable — the unified `nirimaki <group> <action>`
form is the user-friendly surface; keybinds.kdl and .desktop entries
still invoke the bare scripts.

## User customisation surface (Omarchy parity)

Users extend Nirimaki by editing the user-side files listed below,
NEVER by editing files under `default/` or other repo-owned paths
(which would break the upgrade path).

| Want to…                                 | Edit                                                    |
|------------------------------------------|---------------------------------------------------------|
| Configure monitors                       | `~/.config/niri/monitors.kdl`                           |
| Add / override / "unbind" niri keybinds  | `~/.config/niri/bindings.kdl`                           |
| Override niri input (keyboard layout…)   | `~/.config/niri/input.kdl`                              |
| Add niri window-rules                    | `~/.config/niri/windows.kdl`                            |
| Add niri spawn-at-startup                | `~/.config/niri/autostart.kdl`                          |
| Customise foot (font, keybinds, padding) | `~/.config/foot/foot.ini`                               |
| Customise tmux                           | `~/.config/tmux/tmux.conf`                              |
| Customise fish (path, abbrs, prompt…)    | `~/.config/fish/config.fish`                            |
| React to theme change                    | `~/.config/nirimaki/hooks/theme-set.d/<name>` (+x)      |
| React to webapp install/remove           | `~/.config/nirimaki/hooks/{webapp-installed,webapp-removed}.d/<name>` (+x) |
| Add / override a SettingsMenu entry      | `~/.config/nirimaki/extensions/menu.json`               |
| Override how an app gets themed          | `~/.config/nirimaki/themed/<base>.tpl`                  |

The niri + foot + tmux + fish user files are SEEDED ONCE by
`dev-link.sh` / `install.sh` (copy, not symlink), so edits survive
`git pull` or `nirimaki upgrade`. Quickshell + nvim + themes are
repo-owned — symlinked in dev, copied (and overwritten) on upgrade
by install.sh. foot + tmux specifically follow Omarchy's whole-file
user-owned model (no defaults-vs-user layering — what we ship is the
starting point and the user owns it from there); only foot's
runtime theme palette stays upgrade-tracked via the
`include=~/.config/theme/current/foot.ini` directive at the top of
the user's foot.ini.

`~/.config/nirimaki/*` samples shipped at `config/nirimaki/<dir>/*.sample`.
See `docs/phase-j-platform.md` for the schema details.

## What's deferred

- **`install.sh` + `packages.txt`**: blank-Arch → Nirimaki. Copy
  (not symlink) so a later `git pull` doesn't clobber a user's
  tweaks. Live code is now portable across users — `keybinds.kdl`
  uses `spawn-sh "$HOME/..."` and QML uses
  `Quickshell.env("HOME") + …`, so no per-user path templating is
  needed. The one exception is qt5ct/qt6ct (`color_scheme_path=`),
  which doesn't expand env vars — install.sh has to write that
  line with the target user's literal home. Per-phase install
  requirements are documented at the bottom of each phase doc —
  see `docs/phase-i-webapps.md` for chromium policy-dir chmod and
  the `xdg-settings` initial default-browser step, and
  `docs/phase-j-platform.md` for the `~/.config/nirimaki/`
  sample-copy step.

## What NOT to do

- Don't run `git config --global` (see above).
- Don't add `~/.local/bin/` symlinks for `nirimaki-*` to system-wide
  paths — they need to live in the user's `~/.local/bin/`.
- Don't reformat untouched code when making targeted edits.
- Don't write planning docs / analysis files unless asked. Update
  phase docs only when behaviour actually changes.
- Don't symlink `~/.config/theme/current/` — see above.
