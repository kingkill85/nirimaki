# Quickshell migration — session handoff

Read this first if you're picking up the Quickshell-migration work and
the previous Claude session has timed out. It captures the cross-
cutting state, the gotchas paid for in blood across Phases L–O, and
where each remaining group plugs in.

## TL;DR

The big migration described in
[`quickshell-migration-plan.md`](quickshell-migration-plan.md) is
**nearly done**: the UI primitives, the plugin-kinds lifecycle, the
shell.json config, and all three service-backed plugins (audio +
bluetooth + network, each with its tabbed panel) are in. Only the
Group G cleanup pass remains.

Run the dev gallery to eyeball the kit:

```bash
quickshell ipc call shell summon dev-gallery
quickshell ipc call shell hide   dev-gallery
```

Open the audio mixer:

```bash
quickshell ipc call shell summon audio
# or Settings menu → Setup → Audio
# or right-click the audio pill on the bar
```

## What shipped

| Layer            | What's there                                                          |
|------------------|-----------------------------------------------------------------------|
| **UI primitives**| `BarPill`, `BarPopover`, `Button`, `Dropdown`, `SearchableDropdown`, `NumberField`, `PanelSlider`, `PopoverActions`, `PopoverButton`, `PopoverDivider`, `PopoverHeader`, `TabBar`, `TextField`, `Toggle`, `Tooltip` — all in `config/quickshell/`, all registered in `qmldir`. |
| **Plugin kinds** | Manifest schema v2 (`kinds: []`, `entryPoints: {kind: filename}`); lazy `overlay` / `panel` / `menu` loaders in `shell.qml`; shell-level IPC at target `shell` (`summon` / `hide` / `toggle` / `listPlugins` / `rescanPlugins`). |
| **shell.json**   | `Config.qml` singleton reads `~/.config/nirimaki/shell.json`; Plugins.qml derives bar order from it when valid (legacy `plugins.json` is the fallback). Inline per-widget settings flow through `byMount[mount][i].settings`. |
| **Migrator**     | `bin/nirimaki-config-migrate` — idempotent, run by `install/config.sh` on install and by `migrations/1779702575.sh` on upgrade. |
| **AudioService** | `config/quickshell/AudioService.qml` — wraps `Quickshell.Services.Pipewire`. Exposes default sink/source, sink/source lists, per-app stream lists, **per-process stream groups**, plus setters and per-stream / per-group helpers. |
| **Audio plugin** | Two-surface plugin under `plugins/builtin/audio/`: `BarWidget.qml` (compact popover) + `Panel.qml` (full mixer with Output / Input / Apps tabs, per-process app grouping with expandable sub-rows, sink+source pickers, per-app sliders). |
| **BluetoothService** | `config/quickshell/BluetoothService.qml` — wraps `Quickshell.Bluetooth` (BlueZ). Exposes default adapter + typed device sublists (connected / paired / available), per-device controls, BlueZ-icon → Nerd-Font glyph mapping. |
| **Bluetooth plugin** | Two-surface plugin under `plugins/builtin/bluetooth/`: `BarWidget.qml` (icon + connected-count badge + compact popover) + `Panel.qml` (full device manager with Devices / Adapter tabs, scan toggle, contextual per-row actions, "adapter off" empty state). |
| **NetworkService** | `config/quickshell/NetworkService.qml` — wraps `Quickshell.Networking` (NetworkManager via DBus). Exposes wifiEnabled, primaryDevice/primaryNetwork, typed device sublists, deduped+sorted accessPoints, scan helpers, connect/disconnect/forget, signal-bar mapper, localised state/connectivity labels. |
| **Network plugin** | Two-surface plugin under `plugins/builtin/network/`: `BarWidget.qml` (signal-bar/ethernet pill + compact popover with top 3 APs) + `Panel.qml` (Wi-Fi tab with full SSID list and inline PSK prompt; Wired tab with per-interface state + autoconnect). |
| **i18n**         | Audio + bluetooth + network surfaces are fully localised; keys live under `audio.*` / `bluetooth.*` / `network.*` in `config/quickshell/i18n/{en,de}.json`. |
| **Bar widgets**  | Audio: right-click → mixer, scroll = volume. Bluetooth: right-click → panel, count badge when ≥1 connected. Network: right-click → panel, pill glyph switches between signal bars / ethernet / off. All three left-click → compact popover. |
| **Dev gallery**  | `plugins/builtin/dev-gallery/` — first `kind: overlay` consumer; renders every primitive for visual QA. |

## Gotchas worth paying attention to

These are real bugs the previous session hit and resolved. Don't
re-discover them.

### 1. Two layer surfaces on the same `WlrLayer` route input ambiguously

`DialogShell` originally had the scrim and the dialog both on
`WlrLayer.Overlay`. niri's input routing sent clicks inside the
dialog area to the *scrim* (because it's the bigger surface),
causing every click in any new panel to close it. Fix in place:

- Scrim sits on `WlrLayer.Top`
- Dialog sits on `WlrLayer.Overlay` (one layer higher)

If a future dialog still "closes on every click", check `WlrLayer`
assignment first.

### 2. Quickshell IPC functions need typed parameters

```qml
function summon(id: string, payload: string): string { ... }
```

Untyped (`function summon(id, payload)`) errors at load with
`Type of argument 1 (id: QVariant) cannot be used across IPC`.

### 3. `UntypedObjectModel` → use `.values`

`Pipewire.nodes` and similar live-updating object models are
`UntypedObjectModel`. Iterate via `.values`:

```javascript
const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
```

### 4. `mapToItem(...)` isn't binding-reactive

If you bind a popup's `anchor.rect.x` to `something.mapToItem(...)`,
the value freezes at component construction time (before layout).
Recompute on every show:

```qml
function open() {
    listWin.anchor.rect.x = root.mapToItem(win.contentItem, 0, 0).x;
    root._open = true;
}
```

Both `BarPopover` and `Dropdown` use this pattern.

### 5. ScrollView's `parent.width` doesn't propagate to its content

`Column { width: parent.width }` inside `ScrollView { ... }` collapses
the column to its widest child's implicit width. Layout looks
squashed and `MouseArea`s get zero hit-area.

Fix: use `Flickable` directly with explicit `contentWidth: width` and
`Column { width: flickable.width }`.

```qml
Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    Column {
        id: content
        width: flick.width
        ...
    }
}
```

### 6. In-scene popup lists get clipped + can't be hit-tested

A `Rectangle` positioned at `y: parent.height + 4` to act as a
dropdown drop-list works visually but:

- Flickable's `clip: true` cuts off anything outside its viewport.
- Qt's hit-test does not recurse into children that fall outside
  the parent's bounding rect — clicks at those positions go to a
  sibling Item underneath.

Fix: use `PopupWindow` for the drop list. It creates a separate
Wayland surface, escapes all containers, and gets its own input
focus.

`Dropdown.qml` and `SearchableDropdown.qml` do this; both also
flip the popup upward when there's not enough room below.

### 7. PipeWire stream classification — flags > `media.class`

Many PwNodes (HDMI sink, SteelSeries headset, motherboard audio,
even per-app browser streams) have **empty** `media.class`. Don't
classify by class string — use the flags + audio sub-iface:

```javascript
function _isSinkDevice(n) {
    return n && n.isSink && !n.isStream && n.audio;
}
function _isSinkStream(n) {
    return n && n.isStream && n.isSink && n.audio;
}
```

Source/monitor exclusion still needs the class check (monitors are
sources with `media.class` containing `Monitor`).

### 8. Browsers fan out one PwNode per audio source

Zen / Firefox / Chromium create one PwNode per `<audio>`/`<video>`
element plus a master "AudioStream" node — all sharing
`application.process.id`. Showing them as five rows is confusing
and the per-tab streams often *ignore* volume writes; only the
master is effective.

`AudioService.sinkStreamGroups` partitions by PID. `Panel.qml`'s
Apps tab uses these groups: one row per process with the master
slider writing the new volume to **every** stream in the group
(no-op on the unresponsive per-tab streams; the master receives
the change). Click the row to expand and see / mute individual
streams.

### 9. PipeWire's preferred default IS persisted

`Pipewire.preferredDefaultAudioSink = node` writes through
`wireplumber` to user metadata that survives reboot. No extra
state to keep in shell.json. The audio panel's "Currently: …"
hint was removed because the dropdown's own header already shows
the active default.

## Project structure cheat-sheet

```
config/quickshell/
├── shell.qml              # ShellRoot — bar host + lazy overlay/panel/menu Variants
├── Bar.qml                # one PanelWindow per screen, hosts bar plugins
├── DialogShell.qml        # scrim + dialog two-surface wrapper (used by every overlay/panel)
├── BarPill.qml            # uniform bar-widget chrome + tooltip
├── BarPopover.qml         # anchored bar-popover card
├── Popover{Header,Divider,Button,Actions}.qml
├── {Toggle,PanelSlider,Dropdown,SearchableDropdown}.qml
├── {TextField,NumberField,Button,Tooltip,TabBar}.qml
├── Theme.qml              # palette + token reservoir
├── Plugins.qml            # singleton, registry + summon API + shell IPC
├── Config.qml             # singleton, parses ~/.config/nirimaki/shell.json
├── AudioService.qml       # singleton, wraps Pipewire (the FIRST service)
├── BluetoothService.qml   # singleton, wraps Quickshell.Bluetooth (BlueZ)
├── NetworkService.qml     # singleton, wraps Quickshell.Networking (NetworkManager)
├── NiriService.qml        # singleton, niri IPC (existing)
├── NotificationService.qml # singleton, DBus notifications (existing)
├── UpdatesService.qml     # singleton, paru/pacman (existing)
├── PopupBus.qml           # singleton, single-popup gate
├── I18n.qml               # singleton, locale lookup
├── i18n/{en,de}.json      # locale strings
└── qmldir                 # registers every Singleton + Component

plugins/builtin/
├── audio/
│   ├── plugin.json        # kinds:[bar-widget, panel] + entryPoints
│   ├── BarWidget.qml      # bar pill + compact popover
│   └── Panel.qml          # full mixer overlay (Output/Input/Apps tabs)
├── bluetooth/
│   ├── plugin.json
│   ├── BarWidget.qml      # icon + count badge + compact popover
│   └── Panel.qml          # device manager (Devices/Adapter tabs)
├── network/
│   ├── plugin.json        # kinds:[bar-widget, panel]
│   ├── BarWidget.qml      # signal/ethernet pill + compact popover
│   └── Panel.qml          # connection manager (Wi-Fi/Wired tabs)
├── dev-gallery/
│   ├── plugin.json        # first kind:overlay plugin
│   └── DevGallery.qml
└── (24 other plugins)     # workspaces, calendar, weather, updates, …

bin/nirimaki-config-migrate # plugins.json → shell.json, called by install + migrations
migrations/                 # one-shot upgrade hooks
default/niri/bindings.kdl   # no shipped keybind for service panels — settings menu is the entry
```

## Bluetooth design notes (Phase P, already shipped)

`Quickshell.Bluetooth` is a first-class QML module (not raw DBus) —
`BluetoothAdapter` / `BluetoothDevice` are reactive QObjects with the
right properties already named usefully (`enabled`, `discovering`,
`discoverable`, per-device `connected`, `paired`, `pairing`, `trusted`,
`battery`, etc.). `BluetoothService` is therefore much thinner than
`AudioService` — no PwObjectTracker, no per-process grouping, no
bespoke node classification. It's mostly typed sublists
(`connectedDevices` / `pairedDevices` / `availableDevices`), an icon
mapper (BlueZ `icon` strings → MDI glyphs), and an IPC dump handler.

One quirk: `BluetoothService.deviceSubtitle(d)` returns localised
status text and reads the strings from `_connectedLabel` /
`_pairedLabel` / `_pairingLabel` properties on the service. The Panel
writes those properties on construction and on locale change. Reason:
keep the service free of I18n dependency so it can be imported
anywhere — the panel is the natural locale-aware consumer. Callers
that want raw keys use `deviceState(d)` which returns
`"connected"|"paired"|"pairing"|"available"`.

Pairing devices that require PIN/numeric confirmation will fail
silently — `Quickshell.Bluetooth` doesn't register a BlueZ Agent1, so
the system's own agent has to handle it. Documented as a follow-up in
`phase-p-bluetooth.md`.

## Network design notes (Phase Q, already shipped)

`Quickshell.Networking` is a first-class QML module wrapping
NetworkManager — much like `Quickshell.Bluetooth` wraps BlueZ. The
service exposes typed sublists (wifiDevices, wiredDevices), a deduped
+ sorted access-point view (one row per SSID, connected → known →
strongest), a `signalBars()`/`signalIcon()` mapper from 0..1 ratio to
0..4 bars, and an inline PSK prompt in the panel's wifi rows for
unknown secured networks.

NetworkManager is the **only** backend `Quickshell.Networking` supports
right now, so Group F committed Nirimaki to NM. `install.sh` enables
`NetworkManager.service` and disables `systemd-networkd.service` (both
running at once races for interfaces — IP flapping, DNS clobbering).
`migrations/1779716834.sh` does the same flip for existing installs;
warns (doesn't disable) on `dhcpcd.service` since some users
intentionally run it.

Deferred from this phase: hidden SSID entry, VPN section, saved-only
profile management (NMSettings listing without a live AP), WPA-EAP
enterprise UX. See `phase-q-network.md` for the full list.

## Picking up Group G (Cleanup)

- Audit right-click handlers across plugins — every service-backed
  bar pill right-clicks into its panel.
- Decide whether `wiremix`, `bluetui`, `impala` stay in
  `packages.txt` (probably yes, as optional power-user tools).
- Migrate the remaining "legacy" overlay plugins (launcher,
  emoji-picker, clipboard-picker, theme-picker, power-menu,
  background-picker, language-picker) to `kinds: ["overlay"]` with
  lazy summon. Their existing `mount: overlay` + own `IpcHandler`
  pattern keeps working unchanged today, so this is purely a
  cleanup pass.
- Write a top-level `phase-r-cleanup.md`.

## Things you'll want to know about the running system

- The shell host is `~/.config/quickshell/shell.qml` → symlink to
  `~/Projekte/kingkill85/nirimaki/config/quickshell/shell.qml`
  (this is dev-link.sh's doing). Edit and restart.
- Restart: `pkill quickshell; quickshell -p ~/.config/quickshell/shell.qml &`
- Quickshell IPC: `quickshell ipc call <target> <fn> [args...]`
- Logs: `quickshell log` (filter with `grep -iE 'error|warn|fail'` —
  there's noise from "Qt 6.11" mismatch you can `grep -v` out).
- niri reload: automatic on bindings.kdl save.

## Where to point follow-on questions

- Layout / UI primitives → `docs/phase-l-ui-kit.md`
- Plugin lifecycle / IPC → `docs/phase-m-plugin-kinds.md`
- shell.json schema → `docs/phase-n-shell-json.md`
- AudioService / mixer → `docs/phase-o-audio.md`
- BluetoothService / device manager → `docs/phase-p-bluetooth.md`
- NetworkService / connection manager → `docs/phase-q-network.md`
- Big picture → `docs/quickshell-migration-plan.md`
- Project conventions → `CLAUDE.md`
