# Phase R — Cleanup + polish ✅

Group G of the [Quickshell migration plan](quickshell-migration-plan.md).
Final pass after the three service-backed plugins (audio / bluetooth /
network) landed in Phases O–Q. Migrates the remaining nine legacy
overlay plugins from schema v1 (`mount: overlay` + per-plugin
`IpcHandler`, eagerly loaded at shell startup) to schema v2 (`kinds:
["overlay"|"menu"]` + lazy-summoned by the shell host), and confirms the
service plugins' right-click → panel wiring already audited.

## What shipped

### 1. Right-click audit — confirmed

All three service-backed bar plugins already route right-click into
their panel:

| Plugin   | File                                | Handler                  |
|----------|-------------------------------------|--------------------------|
| audio    | `plugins/builtin/audio/BarWidget.qml:33` | `onRightClicked: root.openMixer()` |
| bluetooth| `plugins/builtin/bluetooth/BarWidget.qml:49` | `onRightClicked: root.openPanel()` |
| network  | `plugins/builtin/network/BarWidget.qml:101` | `onRightClicked: root.openPanel()` |

`system-stats` keeps its right-click → btop (no service panel exists
for it). `tray` and `active-window` retain their own right-click
semantics (tray app menu, window actions). No code changes needed.

### 2. Legacy overlays → schema v2

Nine plugins migrated. For each:

- Manifest: dropped `mount: overlay` + legacy `ipc` field; added
  `kinds: ["overlay"]` (or `["menu"]` for `settings-menu`) and
  `entryPoints: { overlay: "main.qml" }`.
- QML: dropped the per-plugin `IpcHandler { target: "<id>" … }`.
  `Component.onCompleted: opened = true` snaps to open the moment
  the host instantiates the QML (which only happens when summoned).
  `onOpenedChanged`'s false-branch now calls `Plugins.hide("<id>")`
  so closing tears the QML down via the outer summon-Loader.
- Inner content-Loader's `active: root.opened || root._everLoaded`
  became `active: true`; the `_everLoaded` cached-instance trick is
  obsolete because the outer summon-Loader now provides that
  lifecycle.

Migrated plugins:

| Plugin              | Kind     | Trigger                                                                |
|---------------------|----------|------------------------------------------------------------------------|
| `launcher`          | overlay  | `quickshell ipc call shell toggle launcher ""`                         |
| `emoji-picker`      | overlay  | `quickshell ipc call shell toggle emoji-picker ""`                     |
| `clipboard-picker`  | overlay  | `quickshell ipc call shell toggle clipboard-picker ""`                 |
| `theme-picker`      | overlay  | `quickshell ipc call shell toggle theme-picker ""`                     |
| `power-menu`        | overlay  | `quickshell ipc call shell toggle power-menu ""`                       |
| `background-picker` | overlay  | `quickshell ipc call shell toggle background-picker ""`                |
| `language-picker`   | overlay  | `quickshell ipc call shell toggle language-picker ""`                  |
| `keybind-sheet`     | overlay  | `quickshell ipc call shell toggle keybind-sheet ""`                    |
| `settings-menu`     | menu     | `quickshell ipc call shell toggle settings-menu ""`                    |

The trailing `""` is the (unused) `payload` arg — the shell's
`toggle`/`summon` IPC functions are typed `(id: string, payload:
string)` and IPC rejects calls that omit a required argument. The
existing v2 plugins (audio/bluetooth/network panels, dev-gallery) had
to follow the same pattern.

### 3. Cross-references updated

- **`default/niri/bindings.kdl`** — every binding that previously
  called `quickshell ipc call -- <id> toggle` was rewritten to call
  `quickshell ipc call shell toggle <id> ""`. The Mod+F1, Mod+Space,
  Mod+Ctrl+V, Mod+E, Mod+Ctrl+Space, Mod+Shift+Ctrl+Space, Mod+Escape,
  Mod+Alt+Space bindings cover the eight summonable surfaces above.
- **`config/quickshell/settings-menu.json`** — three entries with
  `{ "type": "ipc", "target": "theme-picker" }` (and the same shape
  for `background-picker` and `keybind-sheet`) switched to
  `{ "type": "summon", "id": "<id>" }`. The `summon` action type was
  already implemented in `SettingsMenu._dispatch`; this just routes
  the cross-references through it. The action-types comment block at
  the top of `settings-menu.json` now documents `summon` alongside
  `ipc`.
- **`install/verify.sh`** — `quickshell ipc call -- settings-menu
  ping` became `quickshell ipc call shell ping` (the per-plugin ping
  handlers no longer exist, but `shell` has its own).
- **`bin/nirimaki-locale-set`** — comment-only fix; the user-facing
  invocation hint now reads `shell summon language-picker`.

### 4. Decision on TUI escape hatches

`install/packaging.sh:66` still installs `wiremix` and `bluetui`. The
Phase O/P decision was to keep them as optional power-user CLIs (right-
click on the audio/bluetooth pill no longer launches them, but `wiremix`
and `bluetui` remain available from a terminal). `impala` (Wi-Fi TUI)
was already dropped during Phase Q. **No change in this phase.**

## How the new lifecycle looks

```
keybind / IPC call ─▶ shell.toggle(id, "")
                      └─▶ Plugins.summon(id)
                          └─▶ Plugins.summoned[id] = true
                              └─▶ outer Loader in shell.qml flips active=true
                                  └─▶ plugin's main.qml instantiated
                                      └─▶ Component.onCompleted: opened = true
                                          └─▶ onOpenedChanged → PopupBus.show(root)
                                              └─▶ DialogShell visible

Escape / click outside / leaf-action ─▶ root.opened = false
                                        └─▶ onOpenedChanged
                                            ├─▶ PopupBus.hide(root)
                                            └─▶ Plugins.hide(id)
                                                └─▶ summoned[id] cleared
                                                    └─▶ outer Loader flips active=false
                                                        └─▶ plugin QML unloaded
                                                            (state resets on next summon)
```

This matches the `dev-gallery` overlay pattern (the first v2 overlay
consumer, shipped in Phase M) and the audio / bluetooth / network
panels (Phases O–Q).

## Verification

- `niri validate -c ~/.config/niri/config.kdl` — clean.
- `quickshell ipc call shell listPlugins` — all 9 migrated plugins
  show `kinds=["overlay"|"menu"]` and an empty `mount` field, meaning
  they're routed through `byKind` (lazy) instead of `byMount` (eager).
- `quickshell ipc call shell summon <id> ""` followed by
  `quickshell ipc call shell hide <id>` round-trips cleanly for every
  migrated plugin; `summoned` flips true → false and the dialog
  appears/disappears as expected.

A pre-existing "Binding loop detected for property `active`" warning
appears once at quickshell startup. It traces to the
`Loader.active: Plugins.isSummoned(modelData.id)` line in
`shell.qml`'s lazy-summon Variants and was already in the log under
Phases M–Q (dev-gallery + audio/bluetooth/network panels), so it
predates this migration. Harmless given that summon/hide round-trip
works end-to-end; left as-is.

## Out of scope (deferred)

These came up while pulling on the cleanup thread but stay out:

- **Make payload optional on `shell.toggle` / `shell.summon`.** The
  required-payload signature means every keybind has to pass a
  trailing `""`. Quickshell IPC argument typing is fixed at the
  IpcHandler-function declaration site; either splitting into two
  overloads (`summon0(id)` + `summon1(id, payload)`) or relaxing the
  typed signature would simplify keybinds slightly. Not worth the
  churn for one extra string per binding.
- **Bar settings *visual editor*.** Schema is already in `shell.json`;
  the drag-drop reorder + per-widget setting form is the follow-up.
- **Plugin-host UX**: enable/disable a plugin from the settings menu,
  install/uninstall a third-party plugin from a URL. The loader has
  the registry and `rescan()` already; what's missing is the UI.
- **NightLight / DnD / StayAwake / Reminders / Polkit plugins** — each
  is its own future phase.
- **Indicators-cluster widget** (hover-reveal status-icon cluster, à
  la Omarchy) — nice cleanup, defer until DnD/NightLight are in to
  populate it.

These were all listed as out-of-scope in
`docs/quickshell-migration-plan.md:248` and remain so — Phase R
doesn't touch them.

## Files this phase touched

- `plugins/builtin/launcher/{plugin.json,main.qml}`
- `plugins/builtin/emoji-picker/{plugin.json,main.qml}`
- `plugins/builtin/clipboard-picker/{plugin.json,main.qml}`
- `plugins/builtin/theme-picker/{plugin.json,main.qml}`
- `plugins/builtin/power-menu/{plugin.json,main.qml}`
- `plugins/builtin/background-picker/{plugin.json,main.qml}`
- `plugins/builtin/language-picker/{plugin.json,main.qml}`
- `plugins/builtin/keybind-sheet/{plugin.json,main.qml}`
- `plugins/builtin/settings-menu/{plugin.json,main.qml}`
- `default/niri/bindings.kdl`
- `config/quickshell/settings-menu.json`
- `install/verify.sh`
- `bin/nirimaki-locale-set`
