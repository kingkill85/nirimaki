# Phase K — Plugin system ✅

Decomposed the Quickshell layer into a tiny host + a flat tree of
plugins. Every bar widget, dialog overlay, OSD bezel and notification
toast that used to live under `config/quickshell/` now ships as a
self-contained plugin under `plugins/builtin/<id>/`. The host is down
to 11 QML files; everything that looks like a widget is a plugin.

## What shipped

### 1. Plugin loader (`Plugins.qml`)

A singleton that scans two roots on startup:

```
~/.local/share/nirimaki/plugins/builtin/<id>/plugin.json   first-party (repo)
~/.config/nirimaki/plugins/<id>/plugin.json                third-party (user-installed)
```

Discovery runs once via a single bash pipe that emits one JSON line per
manifest — each line includes the manifest fields plus `dir` (absolute)
and `installed` (whether `requires.binary` resolves on PATH). The
loader keeps the registry on a property; bar/overlay hosts bind to
`Plugins.byMount` and refresh on file watches.

### 2. Manifest format

```jsonc
{
  "id":          "voxtype",
  "name":        "Voxtype",
  "description": "...",
  "version":     "1.0.0",
  "author":      "nirimaki",
  "mount":       "bar.center",   // bar.left | bar.center | bar.right
                                 // | overlay | bezel | toast | event
  "after":       "updates",      // sort hint within mount (id-ref)
  "before":      "other-id",     // alternative to `after`
  "entry":       "main.qml",     // Loader.source target
  "api":         1,              // plugin host API major
  "ipc":         "voxtype",      // optional, for documentation; the
                                 //   handler lives in the plugin QML
  "requires": {
    "binary":       "voxtype",   // command -v gate; missing → silent skip
    "install_hint": "..."        // shown in plugin manager (future)
  }
}
```

There is **no** shipped `default/plugins.json`. Defaults are computed
from the manifests themselves — a new built-in plugin auto-appears in
its declared mount with no merge step, no migration file.

### 3. User overrides — `~/.config/nirimaki/plugins.json`

niri-style per-plugin last-wins. Seeded once with a documented
comment header, never overwritten thereafter. Schema:

```jsonc
{
  "voxtype":  false,
  "weather":  { "mount": "bar.left", "after": "active-window" },
  "calendar": { "after": "updates" }
}
```

- Missing entry → manifest defaults.
- `false` / `null` → disabled.
- Object → override fields (last-wins per field).
- Keys starting with `_` are ignored — the seed ships with `_comment`
  carrying the schema docs so the user reads the format inside the
  file they're about to edit.

Open it via **Settings → Setup → Edit → Plugins** (which is just a
new target for `nirimaki edit`).

### 4. Host patterns

Two distinct mount-host shapes:

| Mount class | Host | Why |
|---|---|---|
| `bar.left` / `bar.center` / `bar.right` | `Repeater` inside a `Row` in `Bar.qml` | Delegates need a layout parent to position. Loader uses `onLoaded` + feature-detect to inject `barWindow` / `outputName` only into plugins that declare them. |
| `overlay` / `bezel` / `toast` | `Variants` at `ShellRoot` in `shell.qml` | `Repeater` doesn't reliably activate Loaders without a graphical parent; `Variants` is Quickshell's native multi-instantiator for ShellRoot context. Plugins do their own per-screen multiplexing internally (Osd / NotificationToast wrap their PanelWindow in `Variants { model: Quickshell.screens }`). |

### 5. Standard-library primitives

The host exposes reusable QML primitives via the shell's qmldir:

| Primitive | Pattern |
|---|---|
| `DialogShell` | Two-surface scrim + card; niri's compositor blur scoped to the card only |
| `PopupBus` | Single-popup gate — opening one popup dismisses any other |
| `MenuView` | Drilldown menu engine — search, kbd nav, breadcrumb, `visibleWhen` gating. Data-in / signals-out. Used by `SettingsMenu`; any plugin wanting a settings-style panel imports this. |

Plugin QML reaches these (and the singletons `Theme`, `I18n`,
`NiriService`, …) via `import qs` — Quickshell's native module import
that resolves to the shell root folder regardless of where the
importing file lives on disk. No symlinks, no relative paths.

### 6. Plugins shipped (25 first-party)

```
bar.left  (2): workspaces, active-window
bar.center(4): calendar, weather, updates, voxtype
bar.right (8): media, screen-record, tray, notifications,
                bluetooth, network, system-stats, audio
overlay   (9): launcher, power-menu, settings-menu, theme-picker,
                background-picker, emoji-picker, clipboard-picker,
                keybind-sheet, language-picker
bezel     (1): osd
toast     (1): notification-toast
```

The OSD also picked up two unrelated bug fixes during this phase:
per-screen rendering (was hardcoded to the first monitor) and scope
of niri's blur (was full-screen because the PanelWindow was
full-screen; now sized to the bezel).

## What stays core

`config/quickshell/`:

- Host surfaces: `shell.qml`, `Bar.qml`
- UI primitives: `DialogShell.qml`, `MenuView.qml`, `PopupBus.qml`
- Services: `Theme.qml`, `I18n.qml`, `NiriService.qml`,
  `NotificationService.qml`, `UpdatesService.qml`
- Loader: `Plugins.qml`

11 files. The `lock/` subdirectory (the lock-screen quickshell process)
stays out of the plugin system for now — it's a separate process, not
a mounted widget. Future: a `shell`-type mount when lock-screen
customisation becomes a thing.

## Migration

`migrations/1779658256.sh` handles existing installs:

1. Seeds `~/.config/nirimaki/plugins.json` with the documented stub
   if it doesn't exist.
2. Ensures `~/.local/share/nirimaki/plugins/builtin/` resolves to the
   shipped tree — no-op on canonical installs where `REPO_DIR` is
   already `~/.local/share/nirimaki`; creates a symlink on dev
   installs where the repo lives elsewhere.

Fresh installs go through `install/config.sh`, which has equivalent
logic; the migration is the backfill for everyone else.

## Gotchas worth knowing

1. **`import qs` requires Quickshell ≥ 0.2.** Plugins lean on this
   syntax instead of relative-path imports; older Quickshell builds
   would have to fall back to `import "../../_host"` symlinks (the
   pre-discovery hack documented in earlier drafts of CLAUDE.md).

2. **Singleton URL identity matters.** Before switching to `import qs`,
   plugins imported the shell directory via a relative path, which
   gave the QML engine a different URL than `shell.qml`'s own
   directory. Result: the same `pragma Singleton` file got
   instantiated twice (one IpcHandler registration was rejected with
   "Handler was registered but will not be used because another
   handler is registered for target ..."). `import qs` dedups via
   module identity.

3. **`Repeater` doesn't activate Loaders at ShellRoot.** Use
   `Variants` for top-level mounts. Took an embarrassing few minutes
   to find when overlay IPC targets all returned "Target not found"
   after the initial migration.

4. **`required property` blocks `onLoaded`-style late injection.**
   Workspaces had `required property string outputName` because Bar
   used to pass it via property binding at instantiation. After the
   plugin migration the property is set by the Loader's `onLoaded`,
   which fires *after* construction — a `required` property warns
   on the initial frame. Switched to `property string outputName: ""`
   with an empty default; the widget renders nothing for one tick,
   then populates.

5. **OSD blur layer-rule scope.** niri's blur matches namespace
   `^(quickshell|nirimaki-.*)$`. The OSD PanelWindow used to be
   full-screen, so the blur applied to the entire monitor (the bezel
   sat invisible over a blurred desktop). Sizing the surface to the
   bezel (269×68 anchored bottom-center) scopes blur to that area
   — same trick `DialogShell` uses for its card.

## Follow-up work (not in this phase)

- **Settings Menu plugin manager UI** — list installed plugins with
  toggle switches that write to `plugins.json`. The "Plugins" entry
  in Settings is currently just a file-opener via `nirimaki edit`.
- **Third-party plugin registry repo** — `kingkill85/nirimaki-plugins`
  for community contributions; `nirimaki plugin install <id>` clones
  manifest+QML into `~/.config/nirimaki/plugins/<id>/`.
- **More standard-library primitives** —
  - `BarPill` (the hoverable rounded-rect pattern every right-Row
    widget reimplements)
  - `BarPopover` (anchor-to-pill popover card, duplicated by
    Calendar/Weather/Network/Bluetooth/Tray/SystemStats/Media)
  - `Bezel` (transient overlay used by OSD; could be reused for
    notification toasts on simple variants)
- **Migrate overlays' menu actions to plugin contributions** —
  voxtype's `install.ai.voxtype` / `remove.ai.voxtype` entries still
  live in central `settings-menu.json`. Long-term they should travel
  with the voxtype plugin's manifest so install/remove of the plugin
  also surfaces/hides its menu entries.
