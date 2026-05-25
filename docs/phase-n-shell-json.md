# Phase N — shell.json + Config singleton ✅

Group C of the [Quickshell migration plan](quickshell-migration-plan.md).
Replaced the per-plugin `plugins.json` override file with a single
authoritative `shell.json` that owns bar position, positional layout,
and any inline per-widget settings. Legacy `plugins.json` still works
as a fallback; existing installs migrate via a one-shot script that
runs through the `nirimaki-update` migrations chain.

## What shipped

### 1. `~/.config/nirimaki/shell.json`

```jsonc
{
  "version": 1,
  "bar": {
    "position": "top",
    "layout": {
      "left":   [{"id": "workspaces"}, {"id": "active-window"}],
      "center": [{"id": "calendar"}, {"id": "weather"}, {"id": "updates"}, {"id": "voxtype"}],
      "right":  [{"id": "media"}, {"id": "screen-record"}, {"id": "tray"},
                 {"id": "bluetooth"}, {"id": "network"}, {"id": "system-stats"},
                 {"id": "audio"}, {"id": "notifications"}]
    }
  },
  "plugins": []
}
```

Rules:

- **Positional.** Order of entries IS bar order. No more `after` /
  `before` hints once shell.json is in play.
- **Inline settings.** Any key other than `id` on a layout entry is a
  per-widget setting. Example: `{"id": "calendar", "format": "HH:mm"}`.
- **Disable by removal.** A plugin not listed anywhere doesn't load.
- **`version` required.** When the value is missing or unknown,
  Config.qml flags the file invalid and the loader falls back to the
  legacy manifest-derived layout.
- **Reserved**: top-level `plugins[]` array — currently unused, will
  hold entries for non-bar plugins (overlay/panel/menu) once they
  carry their own user-tunable settings.

### 2. `Config.qml` singleton

```
~/.config/nirimaki/shell.json   ←   FileView watch
                ↓
            Config singleton
            ├── valid: bool
            ├── barPosition: string
            ├── barLeft / barCenter / barRight: var[]
            └── settingFor(id, key, fallback)
```

Reads + parses shell.json on startup and on every file change. Exposes
the parsed sections via reactive properties so consumers can bind
directly to them.

### 3. `Plugins.qml` reads from Config when valid

The plugin loader's `_rebuild()` now prefers `Config.barLeft/Center/Right`
when `Config.valid === true`. Each `byMount[mount]` entry carries an
inline `settings` object built from the rest of the shell.json entry
(everything that isn't `id`):

```
shell.json: {"id": "calendar", "format": "HH:mm"}
                       ↓
byMount["bar.center"] entry: {id, dir, entry, mount, settings: {format: "HH:mm"}}
```

Fallback: when `Config.valid === false` (shell.json missing or unsupported
version), the loader uses the legacy manifest+plugins.json path verbatim.
Same algorithm we've shipped since Phase K — no behavioral drift for
fresh-install users between the shell starting up and the migration
having a chance to run.

Non-bar mounts (`overlay` / `bezel` / `toast`) always come from
manifests + plugins.json regardless of `Config.valid`. shell.json's
top-level `plugins[]` array is reserved for these in the future, but
until those plugins start declaring user-tunable settings the
manifest-derived path stays authoritative. (Mid-development bug: the
first draft of `_rebuild` only walked the bar mounts when Config was
valid, which silently dropped every overlay — launcher,
settings-menu, emoji-picker, etc. — the moment shell.json was first
written.)

A `Connections { target: Config }` block re-runs `_rebuild()` whenever
Config's properties change, so hand-edits to shell.json refresh the
bar live without restart.

### 4. `Bar.qml` injects `settings` into plugin Loaders

Same feature-detect pattern as `barWindow` / `outputName`:

```qml
Loader {
    onLoaded: {
        if ("barWindow" in item) item.barWindow = bar;
        if ("outputName" in item) item.outputName = bar.modelData.name;
        if ("settings"   in item) item.settings   = modelData.settings || ({});
    }
}
```

Plugins that want inline settings declare `property var settings: ({})`
and read e.g. `settings.format || "HH:mm"`. Plugins that don't ignore it.

### 5. `bin/nirimaki-config-migrate`

Idempotent migration script. Workflow:

1. If `~/.config/nirimaki/shell.json` exists → exit 0 (no-op).
2. Read every manifest under `~/.local/share/nirimaki/plugins/builtin/`
   and `~/.config/nirimaki/plugins/`.
3. If `plugins.json` is present, apply its per-id overrides
   (`{mount, after, before}` or `false` to disable).
4. Resolve `after` / `before` references per bar mount, producing a
   linear order.
5. Write `shell.json` with the resolved positional layout.
6. Move `plugins.json` → `plugins.json.pre-migration` (backup).

Flags:

- `--force` — regenerate even if shell.json exists (backs up to
  `shell.json.bak` first).
- `--help` — usage.

### 6. Migration entry

`migrations/1779702575.sh` — calls `nirimaki-config-migrate` so the
next `nirimaki-update` on an existing install creates shell.json and
backs up plugins.json. Fresh installs run `install.sh` which already
pre-marks every shipped migration as already-applied; the script
should also be called once explicitly from `install/config.sh` so
fresh installs get a default shell.json. (Followup: see "Install
requirements" below.)

## Design choices worth recording

**Migrator is a script, not a QML routine.** The migration walks
plugin dirs, resolves references, and writes shell.json — all
filesystem work that doesn't need to live in the running shell. A
script that the user can run by hand (`nirimaki-config-migrate`) plus
a migration entry that runs it on update is the same pattern as the
Plymouth / SDDM resync migrations. The shell just reads the result.

**Config and Plugins are separate singletons.** Could have merged them
— Config is just data, Plugins is registry + layout. Keeping them
separate means Config can be reused later for non-plugin settings
(idle timeouts, theme preferences, etc.) without inflating Plugins.

**No `default/shell.json` shipped.** Defaults are computed from
manifests on first migrate. A shipped default file would create a
merge problem when we add new built-in plugins (the user's frozen
defaults wouldn't pick them up). The migrator's logic IS the default.

**Legacy fallback kept.** `Config.valid === false` falls back to the
manifest+plugins.json path. This is a safety net for fresh installs
where the shell starts before install.sh runs `nirimaki-config-migrate`,
or for users who delete shell.json. The bar still renders.

**`property var settings` on plugins is opt-in.** Bar.qml injects only
when the plugin declares the property — same pattern as `barWindow` /
`outputName`. Plugins that don't care about per-instance settings need
no changes.

## What didn't ship

- **Settings forms.** The schema is in place but no plugin reads
  inline settings yet. Calendar's `format`, weather's `lat`/`lon`,
  voxtype's enabled-state — all stay hard-coded for now and will
  start reading `settings.X` as they're touched in later phases.
- **`allowMultiple: true`.** Schema is positional so it could
  technically support multiple entries with the same id (two clocks
  in different timezones). Plugins.qml's byMount currently dedups by
  id since each plugin is a single Loader; supporting multiple
  instances needs a per-entry instance key.
- **Bar settings GUI.** Drag-drop reorder + per-widget setting forms
  — that's a panel-plugin built on top of this schema, in a later
  cleanup phase after the service plugins land.

## Install requirements

- `install.sh` should call `nirimaki-config-migrate` once during
  install so fresh installs ship with a valid `shell.json`. Until
  added, fresh installs run on the legacy manifest-derived fallback
  until first `nirimaki update` triggers the migration.
- `nirimaki-update` already picks up new migrations automatically —
  no install.sh change needed for upgrading users.

## Common ops

| Task                                  | Command                                       |
|---------------------------------------|-----------------------------------------------|
| Migrate now                           | `nirimaki-config-migrate`                     |
| Regenerate (existing config backed up)| `nirimaki-config-migrate --force`             |
| Disable a plugin                      | edit shell.json, remove its layout entry      |
| Reorder a section                     | edit shell.json, reorder the array            |
| Override calendar format              | `{"id": "calendar", "format": "HH:mm"}`       |
| Hand-validate                         | `python3 -m json.tool ~/.config/nirimaki/shell.json` |
