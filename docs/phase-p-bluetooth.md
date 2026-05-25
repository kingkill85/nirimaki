# Phase P — BluetoothService + bluetooth panel ✅

Group E of the [Quickshell migration plan](quickshell-migration-plan.md).
Added the `BluetoothService` singleton that wraps Quickshell's native
`Quickshell.Bluetooth` (BlueZ) bindings; split the bluetooth plugin into
a `BarWidget.qml` (compact pill + popover) and a `Panel.qml` (full
graphical device manager); wired the panel summon path so bluetui is no
longer required tooling.

## What shipped

### 1. `BluetoothService` singleton

`config/quickshell/BluetoothService.qml` — single place every plugin
reads bluetooth state from and writes bluetooth commands to. Wraps
`Quickshell.Bluetooth` and exposes a clean app-facing API:

| Property                | What                                            |
|-------------------------|-------------------------------------------------|
| `adapter`               | `BluetoothAdapter` (default) or null            |
| `present`               | `!!adapter`                                     |
| `enabled`               | adapter powered                                 |
| `state`                 | `BluetoothAdapterState.Enum`                    |
| `busy`                  | `state ∈ {Enabling, Disabling}`                 |
| `discovering`           | scan in progress                                |
| `discoverable`          | visible to other devices                        |
| `devices[]`             | every device on the default adapter             |
| `connectedDevices[]`    | subset where `connected === true`               |
| `pairedDevices[]`       | subset where `paired && !connected`             |
| `availableDevices[]`    | subset where `!paired` (populated by scan)      |

| Method                                | Effect                          |
|---------------------------------------|---------------------------------|
| `setEnabled(b)` / `togglePower()`     | adapter on/off                  |
| `setDiscovering(b)` / `startScan()` / `stopScan()` / `toggleScan()` | scan control |
| `setDiscoverable(b)`                  | visibility to other devices     |
| `connectDevice(d)` / `disconnectDevice(d)` / `toggleConnection(d)` | per-device |
| `pairDevice(d)` / `cancelPair(d)` / `forgetDevice(d)` | pairing lifecycle |
| `setTrusted(d, b)` / `setBlocked(d, b)`| device-level policy            |
| `displayName(d)`                      | `name → deviceName → address`   |
| `deviceIcon(d)`                       | Nerd-Font glyph by BlueZ icon   |
| `deviceSubtitle(d)`                   | status line for list rows (i18n via labels) |
| `deviceState(d)`                      | `"connected"|"paired"|"pairing"|"available"` |

The underlying `Quickshell.Bluetooth` module already provides reactive
properties — no `PwObjectTracker`-style manual subscription needed
here. The service is mostly a re-shaping layer (typed sublists, icon
mapping, IPC) over an already-clean API.

### 2. Bluetooth plugin — two surfaces, one plugin

Schema-v2 manifest mirrors audio's:

```jsonc
{
  "id":          "bluetooth",
  "version":     "2.0.0",
  "kinds":       ["bar-widget", "panel"],
  "entryPoints": {
    "bar-widget": "BarWidget.qml",
    "panel":      "Panel.qml"
  },
  "mount":       "bar.right",       // legacy fallback
  "after":       "notifications",   // legacy fallback
  "entry":       "BarWidget.qml"    // legacy fallback
}
```

- **`BarWidget.qml`** — replaces the old `main.qml`. Bluetooth icon +
  a tiny count badge when ≥1 device is connected. Reads state from
  `BluetoothService` (no more `bluetoothctl show` Process polling).
  Left-click opens a compact popover with adapter status, up to 3
  connected devices, and a power toggle + "manage" button. Right-click
  summons the panel directly.
- **`Panel.qml`** — new, `kind: panel`, lazy-loaded. Full device
  manager built on `DialogShell` (540×560 card). Two tabs:
  1. **Devices** — three sections (Connected / Paired / Available),
     each a Repeater over the matching service list. Available section
     has a Start/Stop scan button in its section header. Every row has
     the contextually-correct action buttons (Disconnect for connected,
     Connect+Forget for paired, Pair for available, Cancel during pairing).
  2. **Adapter** — adapter name + DBus id label, plus three
     `Toggle` rows: Power, Discoverable, Discovering. Discoverable
     and Discovering disable visually when the adapter is off.

The Devices tab has two empty-state branches before the device list
ever renders:
- **No adapter at all** — italic centred message ("No Bluetooth adapter detected.")
- **Adapter off** — large icon + helper text + a "turn on" button.
  Most useful surface when bluetooth is off by default.

### 3. Panel summon paths

The panel opens via the shell IPC, with three triggers:

- **Bar pill right-click** — `BarWidget.qml` calls
  `Plugins.summon("bluetooth")`. Bluetui is no longer the right-click
  target.
- **Settings menu** — `setup.bluetooth` entry changed from
  `{type: "shell", cmd: "rfkill unblock bluetooth; foot ... bluetui"}`
  to `{type: "summon", id: "bluetooth"}`. This is the canonical
  top-level entry point — service panels deliberately get no
  dedicated keybind (settings menu is the discoverable surface).
- **External IPC** — `quickshell ipc call shell summon bluetooth` works
  from any script / user keybind / dmenu entry. Users who want a
  one-key shortcut can wire one in `~/.config/niri/bindings.kdl`.

## Design choices worth recording

**`Quickshell.Bluetooth` is already a clean wrapper.** Unlike the
audio service (which needed `PwObjectTracker` plumbing + per-process
grouping + bespoke node classification), Quickshell ships first-class
QML bindings for BlueZ. `BluetoothAdapter` and `BluetoothDevice` are
reactive QObjects with the right properties already named usefully.
The service is therefore much thinner — mostly typed sublists, icon
mapping, and an IPC handler.

**Device subtitle labels come from the panel, not the service.**
`BluetoothService.deviceSubtitle(d)` reads localised "Connected" /
"Paired" / "Pairing…" strings from `_connectedLabel` / `_pairedLabel`
/ `_pairingLabel` properties that `Panel.qml` writes on construction
and on locale change. Reasoning: the service must stay free of
I18n dependency so it can be imported anywhere (including QML files
that don't load i18n); the panel is the natural locale-aware consumer
that wants those strings in the subtitle. `deviceState(d)` returns the
raw `"connected"|"paired"|"pairing"|"available"` key for callers that
want to do their own labelling.

**Empty-state-when-off is a first-class screen.** Toggling bluetooth
off shouldn't show an empty Devices list — it's a different state.
The Devices tab branches: no adapter → simple message; adapter off →
big icon + Turn-On button; otherwise → real list. The Turn-On button
is the cheapest path to a useful next state.

**Bar-pill count badge.** Connected-device count appears as a small
number next to the icon when ≥1 device is connected. Cheap signal of
"is something playing/listening via BT right now" without needing the
popover. Hidden when count === 0 so the pill stays compact.

**Panel uses `Flickable` (not `ScrollView`).** Same reason as audio's
Apps tab — `ScrollView`'s `parent.width` doesn't propagate to its
content under Quickshell (handoff gotcha 5).

**Bluetui isn't removed.** Still installable, still works from a foot
terminal. It's just no longer the right-click target on the bar pill,
and the settings menu's "Bluetooth" entry now opens the panel. The
Group G cleanup will decide whether bluetui stays in default
`packages.txt`.

## What didn't ship

- **Pairing PIN/confirmation flow.** BlueZ Agent1 is the protocol for
  confirming a numeric PIN during pairing. `Quickshell.Bluetooth` does
  not expose an agent registration; pairing currently relies on the
  external bluez agent (typically the desktop's default one) for the
  PIN dance. For the majority of devices that pair without
  confirmation, this is invisible; pairing devices that do request
  confirmation will fail silently until an agent is up. Deferred.
- **Wake-allowed / Trusted toggles in the device row.** Both are
  exposed on `BluetoothDevice` and wired in the service, but the
  panel keeps the row chrome minimal (icon + name + subtitle + two
  action buttons). A future "Device details" expansion can surface
  them.
- **Multi-adapter support.** `Bluetooth.adapters` is an array; the
  service only uses `defaultAdapter`. Rare on a desktop. Multi-
  adapter users today see only the default; adding a top-of-panel
  picker is straightforward when needed.
- **Discoverable timeout NumberField.** The adapter exposes a writable
  `discoverableTimeout`; the Adapter tab keeps it as a binary
  Discoverable toggle for now (BlueZ default is 180 s, which is
  usually fine). Add later.

## Install requirements

- **No new packages required.** `bluez` + `bluez-utils` are already
  Nirimaki dependencies for the existing `bluetoothctl` and `bluetui`
  flows. `Quickshell.Bluetooth` talks to the same `org.bluez` DBus
  service, so adding the panel costs nothing new.
- **`bluetui` is no longer required tooling.** It can stay installed
  but the bar / settings / keybind no longer launch it. A future
  `packages.txt` audit (Group G cleanup) decides whether to drop it
  from the default install.

## Common ops

| Task                                | Command                                              |
|-------------------------------------|------------------------------------------------------|
| Open bluetooth panel                | Settings menu → Setup → Bluetooth, or `quickshell ipc call shell summon bluetooth` |
| Open compact popover                | Left-click the bluetooth pill                        |
| Open panel from compact popover     | Click "manage" button at the bottom                  |
| Toggle adapter power from anywhere  | Bar pill popover → "turn on" / "turn off"            |
| Start a scan                        | Devices tab → "start scan" in Available header       |
| Pair a new device                   | Devices tab → start scan → click "pair" on the row   |
| Disconnect a connected device       | Devices tab → "disconnect" on its row                |
| Forget a paired device              | Devices tab → "forget" on its row                    |
| Dump live state for debugging       | `quickshell ipc call bluetooth dump`                 |
