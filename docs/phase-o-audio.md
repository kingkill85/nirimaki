# Phase O — AudioService + audio panel ✅

Group D of the [Quickshell migration plan](quickshell-migration-plan.md).
Added the `AudioService` singleton that wraps Quickshell's Pipewire
bindings; split the audio plugin into a `BarWidget.qml` (compact pill
+ popover) and a `Panel.qml` (full graphical mixer); wired the panel
summon path so wiremix is no longer required tooling.

## What shipped

### 1. `AudioService` singleton

`config/quickshell/AudioService.qml` — single place every plugin reads
audio state from and writes audio commands to. Wraps `Pipewire` and
exposes a clean app-facing API:

| Property                          | What                          |
|-----------------------------------|-------------------------------|
| `defaultSink`, `defaultSource`    | active default `PwNode`       |
| `defaultSinkVolume`, `defaultSinkMuted` | shorthand on the default sink |
| `defaultSourceVolume`, `defaultSourceMuted` | shorthand on the default source |
| `sinks[]`, `sources[]`            | all output / input devices    |
| `sinkStreams[]`, `sourceStreams[]`| per-app playback / capture    |

| Method                            | Effect                        |
|-----------------------------------|-------------------------------|
| `setDefaultSink(node)`            | switch default output device  |
| `setDefaultSource(node)`          | switch default input device   |
| `setVolume(node, v)`              | clamped to [0..1]             |
| `setMuted(node, b)`               | direct mute                   |
| `toggleMute(node)`                | mute ↔ unmute                 |
| `adjustDefaultSink(delta)`        | bar pill scroll-wheel hook    |
| `displayName(node)`               | description → nickname → name |
| `streamLabel(stream)`             | `application.name` / `media.name` |
| `streamIcon(stream)`              | Nerd-Font glyph by media.role |

The service owns a `PwObjectTracker` of every node it lists, so the
per-node `audio` sub-iface stays "live" and emits change notifications.
Without that, you can read volumes but won't see updates when another
app changes them — and the mixer panel needs those updates to show
real-time per-app levels.

### 2. Audio plugin — two surfaces, one plugin

Schema-v2 manifest:

```jsonc
{
  "id":          "audio",
  "version":     "2.0.0",
  "kinds":       ["bar-widget", "panel"],
  "entryPoints": {
    "bar-widget": "BarWidget.qml",
    "panel":      "Panel.qml"
  },
  "mount":       "bar.right",       // legacy fallback
  "after":       "system-stats",    // legacy fallback
  "entry":       "BarWidget.qml"    // legacy fallback
}
```

- **`BarWidget.qml`** — formerly `main.qml`. The compact pill +
  popover. Reads from `AudioService` instead of inline Pipewire
  wiring; replaced its bespoke slider with the new `PanelSlider`
  primitive; right-click summons the panel instead of launching
  wiremix.
- **`Panel.qml`** — new, `kind: panel`, lazy-loaded. Full mixer
  overlay built on `DialogShell`. Sections:
  1. **Output device** — `Dropdown` of `AudioService.sinks` for
     switching default, master `PanelSlider` + mute `Button`,
     current % readout
  2. **Applications** — `Repeater` over `AudioService.sinkStreams`,
     one card per app with icon, label, %, per-stream slider, per-
     stream mute
  3. **Input device** — same pattern as Output but on
     `AudioService.sources`

### 3. Panel summon paths

The panel opens via the shell IPC, with three triggers:

- **Bar pill right-click** — `BarWidget.qml` calls
  `Plugins.summon("audio")`. Wiremix is no longer the right-click
  target.
- **Settings menu** — `setup.audio` entry changed from
  `{type: "tui", name: "wiremix", ...}` to `{type: "summon", id: "audio"}`.
  A new `summon` action type in `settings-menu/main.qml` is sugar
  over `quickshell ipc call shell summon <id> <payload>`.
- **External IPC** — `quickshell ipc call shell summon audio` works
  from any script / user keybind / dmenu entry. Service panels
  deliberately get no shipped keybind — the settings menu is the
  canonical top-level entry, and users who want a one-key shortcut
  can wire one in `~/.config/niri/bindings.kdl`.

### 4. `summon` action type in settings-menu

A new schema entry for the menu's action dispatcher:

```jsonc
{
  "action": { "type": "summon", "id": "audio", "payload": {...} }
}
```

Sugar over `{type: "ipc", target: "shell", fn: "summon", args: [...]}`.
The new `args` field on the existing `ipc` action also lands so any
plugin can pass through positional arguments — useful for opening a
panel pre-selected on a specific section in future.

## Design choices worth recording

**Service singleton, not a plugin.** `AudioService` lives next to
`NiriService` in `config/quickshell/`, not under `plugins/builtin/`.
It's headless infrastructure (no UI surface, no kind), and every
plugin that touches audio reads from it. Marking it as `kind: service`
in a manifest would have been an option but doesn't gain anything —
singletons are how QML expresses this cleanly.

**Bar widget kept legacy `mount` fields.** Audio's `plugin.json` has
*both* `kinds: ["bar-widget", "panel"]` AND the legacy `mount: bar.right`
/ `after: system-stats` / `entry: BarWidget.qml`. Reason: when Config
is invalid (fresh install before `nirimaki-config-migrate` runs), the
loader falls back to the legacy manifest path. Without those fields,
audio would silently vanish from the bar on fresh installs until the
migrator runs.

**Panel uses `DialogShell` + `ScrollView`.** Full-screen overlay with
scrim + card, scroll vertically when the per-app list exceeds the
card height. Card is 540×620 — enough room for a typical 2-3 sinks +
2-5 apps + 1 source without scrolling.

**`PanelSlider` per stream.** Each app's slider commits on both
`moved` (every change while dragging) and `released`. Pipewire
volumes are cheap to write per-frame, so per-frame feels best.

**Wiremix isn't removed.** Still installable, still works. It's just
no longer the right-click target on the bar pill, and the settings
menu's "Audio" entry now opens the panel. Users who prefer the TUI
can still launch it from a foot terminal.

## Followups landed after the first draft

The initial Panel.qml went through several rounds of polish against
the real PipeWire setup. Capturing them here so the design choices
don't get re-litigated:

### Tabs (Output / Input / Apps)

`Panel.qml` now opens a single tab at a time (`TabBar` primitive,
new in this phase, also registered in qmldir). Layout per tab:

- **Output** — `DEFAULT OUTPUT` label, sink picker, `VOLUME` slider +
  mute, % readout. No "Currently:" hint — the picker header already
  shows the active default and selecting any row persists it via
  wireplumber.
- **Input** — same shape on `defaultSource`. Hidden when there are no
  sources.
- **Apps** — Flickable list of per-process groups (see below).

### Per-process app grouping

Browsers (Zen / Firefox / Chromium) fan out one PwNode per
`<audio>`/`<video>` element plus a master "AudioStream" — all
sharing `application.process.id`. Showing five identical "Zen" rows
was confusing, and only the master accepts volume writes anyway.

`AudioService.sinkStreamGroups` partitions by PID. Each delegate is
a Rectangle with:

- Header row: icon · app name + " × N" (or media.name when N === 1) ·
  % · expand chevron
- Master slider + mute button — `setGroupVolume` / `toggleGroupMute`
  write to every stream in the group
- Expanded sub-list (visible when count > 1, toggled by clicking the
  row) — one bullet per stream with `media.name` + a per-stream
  mute toggle

### Filter loosening

The original filter required `media.class === "Audio/Sink"` etc.
Many PwNodes have an empty `media.class`. Classification now relies
on `isSink` / `isStream` + the `audio` sub-iface presence; only
sources still check the class string (to exclude monitor pseudo-sources).

A debug helper at `quickshell ipc call audio dump` returns every
PwNode the service can see, classified — keep it for diagnosing
future device weirdness.

### Layout primitives

- `Panel.qml` uses `Flickable` (not `ScrollView`) for the Apps tab —
  `ScrollView` doesn't propagate `parent.width` to its content under
  Quickshell.
- Dropdowns / SearchableDropdowns use `PopupWindow` for the drop
  list (not in-scene Rectangle) — escapes Flickable's `clip: true`
  and the parent-bounds hit-test problem.
- `DialogShell` was tweaked so the scrim is on `WlrLayer.Top` and the
  dialog on `WlrLayer.Overlay` (was: both on `Overlay`). niri routes
  pointer events ambiguously between two surfaces on the same layer
  and was sending dialog-area clicks to the scrim, immediately
  closing the panel. One-layer-up for the dialog fixed it.
- Settings menu got a new `summon` action type that's sugar over
  `quickshell ipc call shell summon <id>` — `setup.audio` entry uses
  it; future panel-summoning menu items follow the same pattern.

### i18n

All audio strings under `audio.*` in `i18n/en.json` + `i18n/de.json`.
Both BarWidget and Panel use `I18n.t(...)`.

## What didn't ship

- **Source monitor meter.** PwNodeAudio exposes a `monitor` channel for
  capture-level metering. The Panel's input section shows mute + slider
  but not a level meter; that's a follow-up.
- **Per-app input streams UI.** `sourceStreams` is wired in the service
  but the panel doesn't render them yet (rare on a desktop — usually
  just the active mic).
- **Sink linking / monitoring.** PwLink / PwLinkGroup are exposed by
  Quickshell but we don't surface them. Power-user feature; deferred.

## Install requirements

- **No new packages required.** Pipewire is already a Nirimaki
  dependency. AudioService just consumes the QML bindings.
- **`wiremix` is no longer required tooling.** It can stay installed
  but the bar / settings / keybind no longer assume it's there. A
  future `packages.txt` audit (Group G cleanup) decides whether to
  drop it from the default install.
- **shell.json is auto-seeded.** Fresh installs run
  `bin/nirimaki-config-migrate` from `install/config.sh` to compute
  the default layout from manifests. Existing installs migrate via
  `migrations/1779702575.sh` on their next `nirimaki-update`. Either
  path produces `~/.config/nirimaki/shell.json` without a separate
  user step.

## Common ops

| Task                                | Command                                              |
|-------------------------------------|------------------------------------------------------|
| Open audio panel                    | Settings menu → Setup → Audio, or `quickshell ipc call shell summon audio` |
| Open compact popover                | Left-click the audio pill                            |
| Open mixer from compact popover     | Click "mixer" button at the bottom                   |
| Adjust default volume from anywhere | scroll on the audio pill, or XF86AudioRaiseVolume key |
| Mute toggle                         | XF86AudioMute, or mixer panel mute button            |
| Switch default output device        | mixer panel → Output device dropdown                 |
