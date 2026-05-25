# Phase M — Plugin kinds + lazy summon ✅

Group B of the [Quickshell migration plan](quickshell-migration-plan.md).
Added the manifest-schema-v2 fields (`kinds`, `entryPoints`), the
`summon` / `hide` / `toggle` API on `Plugins`, the shell-level IPC
handler, and the lazy `overlay` / `panel` / `menu` host Variants in
`shell.qml`. Built the first lazy-overlay plugin (dev-gallery) as
proof. No existing plugin was migrated; every legacy plugin still
loads eagerly via its `mount` field exactly as before.

## What shipped

### 1. Manifest schema v2

A plugin manifest may now declare:

```jsonc
{
  "id":          "dev-gallery",
  "name":        "Dev gallery",
  "description": "Visual preview of every UI primitive.",
  "version":     "1.0.0",
  "author":      "nirimaki",
  "kinds":       ["overlay"],
  "entryPoints": {
    "overlay": "DevGallery.qml"
  },
  "api":         1
}
```

Fields:

- `kinds: []` — one or more of `bar-widget`, `overlay`, `panel`,
  `menu`, `bezel`, `toast`, `service`. Replaces (or augments) the
  legacy `mount` field.
- `entryPoints: {kind: filename}` — one QML entry per kind. A plugin
  with both `bar-widget` and `panel` kinds ships two files
  (`BarWidget.qml` + `Panel.qml`).

Backward compat:

- When `kinds` is absent, `Plugins.qml` infers a single kind from
  the legacy `mount`:
  - `bar.left` / `bar.center` / `bar.right` → `bar-widget`
  - `overlay` / `bezel` / `toast` → respective kind
- When `entryPoints` is absent, the legacy `entry` (default
  `main.qml`) is synthesized into `entryPoints` for every inferred
  kind.

Inferred-kinds plugins stay on the eager `byMount` path. Only plugins
that **explicitly** declare `kinds` opt into the v2 lazy `byKind`
path. This is what keeps the legacy overlays (launcher, emoji-picker,
power-menu, settings-menu, …) working unchanged until they're ported
one at a time.

### 2. `Plugins.qml` extensions

New state:

- `byKind: {}` — parallel to `byMount`, keyed by kind. Only contains
  plugins with explicit `kinds`.
- `summoned: {}` — id → bool, source of truth for lazy plugins.
- `summonPayload: {}` — id → arbitrary object; the most-recent
  summon's payload, cleared on hide.

New API:

```javascript
Plugins.summon(id, payload?)   // flip summoned[id] = true; save payload
Plugins.hide(id)               // flip summoned[id] = false; clear payload
Plugins.toggle(id, payload?)   // summon if hidden, hide if summoned
Plugins.isSummoned(id)         // bool
Plugins.listPlugins()          // array of {id, name, kinds, mount, installed, summoned}
Plugins.entryUrlFor(id, kind)  // file:// URL of a plugin's kind entry
```

### 3. Shell-level IPC handler

`Plugins.qml` registers a single `IpcHandler` with `target: "shell"`:

```
quickshell ipc call shell summon  <id> <json-payload>
quickshell ipc call shell hide    <id>
quickshell ipc call shell toggle  <id> <json-payload>
quickshell ipc call shell listPlugins
quickshell ipc call shell rescanPlugins
quickshell ipc call shell ping
```

This is the entry point for *any* keybind / menu / external script
that wants to open a lazy plugin. Each method has typed parameters
so Quickshell's IPC parser accepts them.

### 4. Lazy host Variants in `shell.qml`

Three new Variants live under `ShellRoot`, parallel to the existing
legacy overlay/bezel/toast hosts:

```qml
Variants {
    model: Plugins.byKind["overlay"] || []
    delegate: Loader {
        required property var modelData
        active: Plugins.isSummoned(modelData.id)
        source: "file://" + modelData.dir + "/" + modelData.entry
    }
}
// + Plugins.byKind["panel"], Plugins.byKind["menu"] — identical pattern
```

`Loader.active` binds to `Plugins.isSummoned(id)`, so the plugin
isn't constructed until the user (or an IPC caller) summons it.
Hiding sets `active: false` → the Loader tears down the plugin and
reclaims its memory.

### 5. Dev-gallery plugin

`plugins/builtin/dev-gallery/` — the first lazy-overlay consumer.
Renders every UI primitive (Toggle, PanelSlider, Dropdown,
SearchableDropdown, TextField, NumberField, Tooltip, Button,
PopoverHeader/Divider/Actions) in one scrollable card so we can
eyeball the kit. Wired to `Plugins.hide("dev-gallery")` on Escape
and on its Close button.

Open it:

```bash
quickshell ipc call shell summon dev-gallery
quickshell ipc call shell hide   dev-gallery
quickshell ipc call shell toggle dev-gallery
```

## Design choices worth recording

**v1 / v2 plugins coexist.** No big-bang port. The `byMount` map
keeps serving plugins that declare `mount` (every shipping plugin
right now), and the new `byKind` map only serves plugins that
explicitly declare `kinds`. The disjoint sets mean nothing
double-loads. Each plugin gets ported when its phase arrives (audio
in Group D, etc.).

**`summoned` lives on the registry, not on the plugin.** Legacy
plugins kept their `opened` property and own IpcHandler — that pattern
still works but isn't required. New plugins read
`Plugins.isSummoned(<own-id>)` (or just stay visible whenever they're
loaded, since `Loader.active` is already gating them).

**No payload format yet.** `summon(id, payload)` accepts a JSON object
that gets stashed at `Plugins.summonPayload[id]`. No plugin uses it
yet — added so the audio panel can later be summoned with
`{"tab": "input"}` to jump straight to a section.

**Sub-IPC stays per-plugin.** A plugin can still register its own
`IpcHandler` for plugin-specific actions (e.g. settings-menu's
`open/openAt`). The shell handler only owns the
summon/hide/toggle/listPlugins lifecycle.

## What didn't ship

- Migration of any existing overlay to the new lazy pattern. Launcher,
  emoji-picker, clipboard-picker, theme-picker, power-menu,
  background-picker, language-picker, settings-menu all stay on the
  legacy eager-mount + their-own-IpcHandler pattern. They'll migrate
  in a later cleanup pass (likely Phase R, after the service plugins
  land) so that the migration happens against a stable target.
- Settings-menu hasn't moved to `kind: menu` for the same reason.
- `service` kind has no eager loader yet — services live as
  singletons in `config/quickshell/` (`NiriService`, future
  `AudioService` etc.), not as plugins. The `service` kind is reserved
  in the schema for when a third-party plugin wants to ship a service.

## Install requirements

None. All changes are QML in `config/quickshell/` + a new plugin
under `plugins/builtin/dev-gallery/`. No new packages, no system
changes, no migration.
