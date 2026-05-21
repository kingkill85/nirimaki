# Phase J — Platform: unified CLI, user-overrides, JSON menu ✅

Omarchy parity for the *platform* surface: one `nirimaki` entry-point,
a small set of well-defined user-override directories under
`~/.config/nirimaki/`, and a JSON-driven SettingsMenu that users can
extend without forking the repo. Implementation footprint stays in
the repo; user customisation lives in `~/.config/nirimaki/`.

## What shipped

### 1. Unified `nirimaki` CLI

`bin/nirimaki` is the dispatcher. Users type:

```
nirimaki theme set tokyo-night
nirimaki theme list
nirimaki webapp install
nirimaki browser default zen
nirimaki audio output volume raise
nirimaki help
```

Routing: stitches args with `-` from the longest prefix down, first
match wins.

```
nirimaki theme set tokyo-night
  → bin/nirimaki-theme-set-tokyo-night     (no — not a binary)
  → bin/nirimaki-theme-set tokyo-night     (yes — exec with arg)
```

Each backing script declares metadata in a header comment block
(scanned in the first 40 lines):

```bash
#!/bin/bash
# nirimaki:group=theme
# nirimaki:summary=Switch the active theme by name
# nirimaki:args=<theme-name>
# nirimaki:hidden=true     # optional — omit from help listing
```

`nirimaki help` builds a grouped listing from those headers. Adding a
new command means dropping a script into `bin/`; no central registry.

The bare names (`nirimaki-theme-set`, `nirimaki-webapp-install`, …)
stay directly executable too, so `keybinds.kdl` / `.desktop` entries
keep working without going through the dispatcher.

### 2. qs-* → nirimaki-* rename

All 14 helper scripts renamed from the incidental `qs-` (Quickshell)
prefix to brand-aligned `nirimaki-`. The `qs-` tag was misleading —
most of these touch niri / fish / foot / GTK / Chromium, not just
Quickshell. One bonus rename for shape: `qs-default-browser-set` →
`nirimaki-browser-default` so the CLI verb sits last:
`nirimaki browser default <name>`.

Wayland app-ids + layer namespaces renamed too for consistency:

| Old                        | New                              |
|----------------------------|----------------------------------|
| `qs-webapp-<slug>`         | `nirimaki-webapp-<slug>`         |
| `qs-quake-term`            | `nirimaki-quake-term`            |
| `qs-theme-picker` etc.     | `nirimaki-theme-picker` etc.     |
| `qs-scrim`                 | `dialog-scrim` (see gotcha below)|

`~/.cache/qs-webapps/` → `~/.cache/nirimaki-webapps/` (per-app
Chromium profiles).

niri's blur layer-rule regex updated to match the new family:
`^(quickshell|qs-.*)$` → `^(quickshell|nirimaki-.*)$`.

`dev-link.sh` prunes stale `~/.local/bin/qs-*` symlinks on rerun so
PATH no longer holds broken entries from earlier installs.

### 3. Hooks subsystem

`bin/nirimaki-hook-run <event> [args...]` execs every file in
`~/.config/nirimaki/hooks/<event>.d/` (sort order, `.sample` /
`.disabled` / dot-files skipped, non-executable skipped, a failing
hook is logged but doesn't abort the chain).

Defined events:

| Event              | Args                       | Fired from                         |
|--------------------|----------------------------|------------------------------------|
| `theme-set`        | `$1=theme-name`            | end of `nirimaki-theme-set`        |
| `webapp-installed` | `$1=slug` `$2=url`         | end of `nirimaki-webapp-install`   |
| `webapp-removed`   | `$1=slug`                  | end of `nirimaki-webapp-remove`    |
| `post-update`      | (none — reserved)          | (placeholder for future)           |

Samples shipped at `config/nirimaki/hooks/<event>.d/*.sample`,
symlinked into `~/.config/nirimaki/hooks/` by dev-link.sh. Users
activate by removing `.sample` and `chmod +x`.

### 4. Extensions — JSON-driven SettingsMenu

`config/quickshell/SettingsMenu.qml` no longer hardcodes its menu
tree. It now FileView-loads two JSON files and merges them:

1. `~/.config/quickshell/settings-menu.json` — shipped default
   (symlinked from `config/quickshell/settings-menu.json`).
2. `~/.config/nirimaki/extensions/menu.json` — user additions
   (optional; loaded on `onLoaded`, silently no-op on `onLoadFailed`).

User entries with the same id as a shipped entry fully replace it
(no deep-merge — surprising); new ids extend.

Schema per node:

```json
{
  "icon":     "<nf-glyph>",
  "labelKey": "<i18n-key>",
  "label":    "<inline-literal>",
  "children": ["<id>", "<id>"],
  "action":   { "type": "...", ...type-specific-fields... }
}
```

Action types (dispatcher = `_dispatch(action)` in SettingsMenu.qml):

| type               | Fields                            | Behaviour                                                       |
|--------------------|-----------------------------------|-----------------------------------------------------------------|
| `ipc`              | `target`, `fn`? (default toggle)  | `quickshell ipc call -- <target> <fn>` (deferred via callLater) |
| `tui`              | `name`, `exec[]`                  | `NiriService.launchTui(name, ...exec)` — floating foot          |
| `shell`            | `cmd` (string)                    | `sh -lc "<cmd>"`                                                |
| `exec`             | `cmd[]`                           | `Quickshell.execDetached(cmd)`                                  |
| `exec-in-foot`     | `appId`, `cmd[]`                  | `foot --app-id=<appId> <cmd...>`                                |
| `quickshell-spawn` | `path`                            | `quickshell -p <path>` (used by the lock entry)                 |

`$HOME` tokens inside any string field are expanded at load time
via `Quickshell.env("HOME")` before dispatch.

### 5. Themed user overrides

`nirimaki-theme-set` now builds the template set from the union of:

1. `~/.config/theme/templates/*.tpl` — shipped (from repo).
2. `~/.config/nirimaki/themed/*.tpl` — user overrides.

Same basename wins from the user dir. Drop a `foot.ini.tpl` into
`~/.config/nirimaki/themed/` and your version replaces the shipped
template. New names there extend the template set (e.g. add a
`kitty.conf.tpl` to bring back kitty theming without touching the
repo).

## Gotcha — scrim layer namespace must NOT match the blur regex

The niri layer-rule regex matches `^(quickshell|nirimaki-.*)$` to
blur the dialog backdrop. The dim scrim (`DialogShell.qml` second
PanelWindow) is a SEPARATE layer surface that must NOT be blurred —
its job is to dim the desktop and catch clicks-outside.

Phase J initial rename accidentally renamed the scrim namespace to
`nirimaki-scrim`, which DID match the regex → blur applied to the
whole-screen scrim → "everything's behind a blur." Fixed by renaming
the scrim namespace to `dialog-scrim` (outside the family).

If you ever add another layer surface in a Quickshell dialog,
remember: **scrim-style surfaces stay outside `nirimaki-*`**.

## What an install.sh must do for this phase

```bash
# Copy ~/.config/nirimaki/ samples once (don't symlink the whole dir —
# users will be adding their own active hooks/extensions/themed
# files there, and we don't want repo-controlled samples to swallow
# them). dev-link.sh does this per-file symlink approach for repo
# devs; an end-user install can plain-copy instead.
install -Dm644 config/nirimaki/extensions/menu.json.sample \
  "$HOME/.config/nirimaki/extensions/menu.json.sample"
install -Dm644 config/nirimaki/themed/README.md \
  "$HOME/.config/nirimaki/themed/README.md"
for hook in config/nirimaki/hooks/*.d/*.sample; do
  rel="${hook#config/nirimaki/}"
  install -Dm644 "$hook" "$HOME/.config/nirimaki/$rel"
done

# settings-menu.json gets symlinked from config/quickshell/ (which
# is already the symlinked dir per the existing pattern), no extra
# step.

# Make sure ~/.local/bin is in PATH for the dispatcher to be on
# `nirimaki` muscle-memory. fish: already done in conf.d/. For
# bash users we add to ~/.bashrc at install time.
grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

`bin/nirimaki` itself is symlinked by dev-link.sh's existing
`nirimaki-*` glob (the bare `nirimaki` matches `nirimaki*` — we
extended the glob to include it).

## Optional-feature install/remove wrapper

Add-on features (Voxtype, Tailscale, Steam — anything that isn't part
of the baseline) ship as a small family of bash scripts:

```
bin/nirimaki-<feature>-install
bin/nirimaki-<feature>-remove
bin/nirimaki-<feature>-status   (optional)
```

…with matching SettingsMenu entries under `install.<category>.<feature>`
and `remove.<category>.<feature>` (the JSON loader builds the tree).

Every install/remove script begins by sourcing
`bin/nirimaki-feature-prelude`, a tiny library that standardises three
things across the whole install surface:

1. **Branded banner** — `nirimaki_banner "<title>" "[subtitle]"` prints
   the Nirimaki ASCII logo (tinted with the active theme's accent
   read from `~/.config/theme/current/colors.toml`) plus a one-line
   title bar. Every install/remove screen looks the same regardless
   of who wrote it.
2. **Single-sudo session** — `nirimaki_sudo_prime` validates the
   user's sudo password ONCE (interactive prompt happens here),
   then spawns a background `sudo -n -v` refresher every 60 s so
   slow `pacman -S` / AUR builds don't outlast the timestamp
   cache. EXIT trap installed so the refresher tears itself down.
   Subsequent `sudo …` calls in the script never re-prompt.
3. **Read-the-output pause** — `nirimaki_pause` is the final
   "Press Enter to close…" line. Used so foot doesn't disappear
   the install/remove output the moment the script returns.

Confirmation prompts are NOT used. The user already consented by
selecting the menu entry. Data-collection prompts (webapp install
asking for name + URL) stay; "Are you sure?" prompts are gone.

Template for adding a new optional feature (`nirimaki-foobar-install`):

```bash
#!/bin/bash
# nirimaki:group=foobar
# nirimaki:summary=Install Foobar (~XX MB)
# nirimaki:requires-sudo=true

set -e
. "$HOME/.local/bin/nirimaki-feature-prelude"

nirimaki_banner "Foobar" "Install"

if command -v foobar >/dev/null 2>&1; then
  echo "Foobar already installed — refreshing config only."
else
  echo "Installing foobar (~XX MB)."
fi

nirimaki_sudo_prime    # only if you call sudo / pacman / paru below

sudo pacman -S --needed --noconfirm foobar
# …post-install config…

[[ -x $HOME/.local/bin/nirimaki-hook-run ]] && \
  "$HOME/.local/bin/nirimaki-hook-run" foobar-installed || true

nirimaki_pause
```

Remove script mirrors with `nirimaki_banner "Foobar" "Remove"`,
the same `nirimaki_sudo_prime`, and `nirimaki_pause` at the end.

## User-facing abstraction map

Future Claude: when a user asks "where do I customise X?" the answer
is one of these four:

| User wants to…                                    | Where to drop a file                                 |
|---------------------------------------------------|------------------------------------------------------|
| React to a theme change                           | `~/.config/nirimaki/hooks/theme-set.d/<name>` (+x)   |
| Add a SettingsMenu entry                          | `~/.config/nirimaki/extensions/menu.json`            |
| Override how an app gets themed                   | `~/.config/nirimaki/themed/<base>.tpl`               |
| Anything else (font size, etc.)                   | … not yet a settings surface — case-by-case          |

Implementation details (the `bin/nirimaki-*` scripts, the menu's
QML, niri's window-rules, …) are **not** user-touchable. Editing
them works in this dev install (where the repo is symlinked in
place) but breaks the upgrade path on an `install.sh`-managed
machine.

## Sources

- [Omarchy `bin/omarchy`](https://github.com/basecamp/omarchy/blob/dev/bin/omarchy) — dispatcher reference (we used ~80 lines of bash vs their ~500)
- [Omarchy `config/omarchy/`](https://github.com/basecamp/omarchy/tree/dev/config/omarchy) — hooks/extensions/themed layout we mirrored
- [Omarchy `config/omarchy/hooks/theme-set.d/show-theme-notification.sample`](https://github.com/basecamp/omarchy/blob/dev/config/omarchy/hooks/theme-set.d/show-theme-notification.sample) — sample-file convention
