# Phase Q — NetworkService + network panel ✅

Group F of the [Quickshell migration plan](quickshell-migration-plan.md).
Added the `NetworkService` singleton that wraps Quickshell's native
`Quickshell.Networking` (NetworkManager) bindings; replaced the
Ethernet-only `network` plugin with a two-surface plugin
(`BarWidget.qml` + `Panel.qml`) that manages both Wi-Fi and wired
connections; wired the panel summon path so impala is no longer the
right answer for "I want to switch SSIDs".

## What shipped

### 1. `NetworkService` singleton

`config/quickshell/NetworkService.qml` — single place every plugin
reads network state from and writes network commands to. Wraps
`Quickshell.Networking` (NetworkManager via DBus) and exposes a clean
app-facing API:

| Property                | What                                            |
|-------------------------|-------------------------------------------------|
| `present`               | NM backend up?                                  |
| `wifiEnabled`           | wifi radio on (NM-level)                        |
| `wifiHardwareEnabled`   | rfkill / hardware kill-switch state             |
| `connectivity`          | None / Portal / Limited / Full                  |
| `devices[]`             | every NetworkDevice (wifi + wired)              |
| `wifiDevices[]`         | subset where `type === Wifi`                    |
| `wiredDevices[]`        | subset where `type === Wired`                   |
| `primaryDevice`         | first connected device (or null)                |
| `primaryNetwork`        | active Network on the primary device            |
| `primaryIsWifi` / `primaryIsWired` | shortcuts for the above            |
| `accessPoints[]`        | every wifi network, deduped by SSID, sorted (connected → known → strongest) |
| `scanning`              | any wifi device currently scanning              |

| Method                                | Effect                          |
|---------------------------------------|---------------------------------|
| `setWifiEnabled(b)` / `toggleWifi()`  | radio on/off                    |
| `setScanning(b)` / `startScan()` / `stopScan()` / `toggleScan()` | scan control |
| `connectNetwork(n)` / `connectWithPsk(n, psk)` | open / known / new-secured |
| `disconnectNetwork(n)` / `forgetNetwork(n)` | remove active or saved profile |
| `disconnectDevice(d)`                 | hard-disconnect a NetworkDevice |
| `setAutoconnect(d, b)`                | per-device auto-connect          |
| `isWifiDevice(d)` / `isWiredDevice(d)`| type predicates (plugins skip the enum import) |
| `signalBars(s)` / `signalIcon(s)`     | 0..1 ratio → 0..4 bars / glyph  |
| `isSecured(n)`                        | true unless `Open`/`Owe`        |
| `securityLabel(t)`                    | enum → "WPA2"/"WPA3"/…          |
| `stateLabel(s)`                       | localised state via panel-fed labels |
| `connectivityLabel()`                 | localised connectivity status   |

The underlying `Quickshell.Networking` module already exposes reactive
`Network` / `NetworkDevice` / `WifiDevice` / `WifiNetwork` /
`WiredDevice` types. The service is mostly a re-shaping layer (typed
sublists, deduped+sorted SSIDs, signal-bar mapping, IPC) over an
already-clean API — parallels to `BluetoothService`.

### 2. Network plugin — two surfaces, one plugin

Schema-v2 manifest:

```jsonc
{
  "id":          "network",
  "version":     "2.0.0",
  "kinds":       ["bar-widget", "panel"],
  "entryPoints": {
    "bar-widget": "BarWidget.qml",
    "panel":      "Panel.qml"
  },
  "mount":       "bar.right",
  "after":       "bluetooth",
  "entry":       "BarWidget.qml"
}
```

- **`BarWidget.qml`** — replaces the old `main.qml`. Reads state from
  `NetworkService` (no more `ip route` polling). The pill glyph
  switches between signal bars (when wifi is the primary), the
  ethernet glyph (when wired is the primary), and a wifi-strength-off
  icon when disconnected. Left-click opens a compact popover with the
  connection header, up to 3 visible-but-unconnected APs, and a
  wifi toggle + "manage" button. Right-click summons the panel.
- **`Panel.qml`** — new, `kind: panel`, lazy-loaded. Full network
  manager built on `DialogShell` (560×600 card). Two tabs:
  1. **Wi-Fi** — Repeater over `NetworkService.accessPoints`. Each row
     shows signal glyph + SSID + security padlock + subtitle (state /
     "Saved · WPA2" / etc.) and contextually-correct actions:
     **Disconnect** for the connected row, **Connect + Forget** for
     known rows, **Connect** for unknown open, **Password…** for
     unknown secured (expands the row into an inline PSK prompt).
     Section header has a scan toggle + wifi-off button.
  2. **Wired** — per-interface card with state, link speed, IP
     address, a Disconnect button when connected, and an
     auto-connect Toggle. Most users have one wired interface; this
     mirrors what `ip` would tell them at a glance.

The Wi-Fi tab has three empty-state branches before any list renders:
- **No NM backend** — italic centred message.
- **No wifi device on the system** — same shape, different copy.
- **Wifi off** — large icon + helper text + "turn on" button. When
  the radio is rfkill'd in hardware, the button is hidden and the
  helper switches to the rfkill copy.

### 3. Panel summon paths

The panel opens via the shell IPC, with three triggers:

- **Bar pill right-click** — `BarWidget.qml` calls
  `Plugins.summon("network")`. Impala is no longer the right-click
  target.
- **Settings menu** — `setup.wifi` (which used to launch impala via
  the `shell` action) renamed to `setup.network` with
  `{type: "summon", id: "network"}`. This is the canonical top-level
  entry point — service panels deliberately get no dedicated keybind.
- **External IPC** — `quickshell ipc call shell summon network` works
  from any script / user keybind / dmenu entry. Users who want a
  one-key shortcut can wire one in `~/.config/niri/bindings.kdl`.

### 4. NetworkManager as the install-time backend

Group F commits Nirimaki to NetworkManager. `Quickshell.Networking`
only has two backends (`None` and `NetworkManager`); the panel
doesn't function without NM. Install and migration changes:

- **`install/packaging.sh` §2b** adds `networkmanager` to
  `_pkg_compositor`'s pacman list and drops `impala` (no longer the
  go-to wifi UI for Nirimaki — left as an optional install via the
  user's own package management).
- **`install/packaging.sh` §2i** flips `_pkg_system_enables`:
  - `sudo systemctl disable --now systemd-networkd.service
    systemd-networkd.socket` (when active)
  - `sudo systemctl enable --now NetworkManager.service`

  Both services racing the same interfaces causes IP flapping, DNS
  clobbering, and conflicting routes. NM has to be the sole manager.
- **`migrations/1779716834.sh`** does the same flip for existing
  installs — installs networkmanager if missing, disables+stops
  networkd, enables+starts NM. Idempotent. Warns (doesn't disable)
  on `dhcpcd.service` since some users intentionally run it.

## Design choices worth recording

**Access-point dedup is by SSID, not BSSID.** A single SSID often
broadcasts from multiple radios / access points (mesh, repeaters);
showing one row per BSSID is noisy. `NetworkService._collectAccessPoints`
groups by `n.name`, keeps the connected entry if present, otherwise
the strongest. The hidden cost: connecting to a specific BSSID isn't
possible from the UI. Not a Nirimaki use case for v1.

**Sort: connected → known → strongest.** Bluetooth panel uses
typed-sublist sections (Connected / Paired / Available); for wifi a
single flat list is more useful because the user almost always
either picks the strongest signal or the one they recognise. The
sort puts both within easy reach without splitting them across
sections.

**PSK prompt is inline, not a modal-on-modal.** Clicking "password…"
on an unknown-secured row swaps the row contents in place to show a
`TextField` + Connect/Cancel buttons. No second dialog, no animation
gymnastics. Cancelling restores the row.

**`pskField.text.length >= 8` is the Connect-button gate.** WPA2-PSK
minimum is 8 chars; sub-8 inputs would just fail at NM. Gating
client-side keeps the failure noise out of the journal.

**State labels live on the service.** Same I18n-injection pattern as
`BluetoothService`: panel writes localised strings to
`NetworkService._stateConnectedLabel` etc. on construction + locale
change. Keeps the service free of `I18n` dependency.

**`primaryDevice` = "first connected".** The first device in
`Networking.devices.values` that reports `connected === true`. Good
enough for v1 — multi-homed systems (wifi + wired + vpn) are rare,
and the bar pill picks whichever NM lists first. The panel shows
every device anyway, so the user can manipulate all of them.

**No "hidden SSID" entry surface.** NM supports it (an SSID typed in
manually), but the v1 UX is "pick from the list". The few users who
need hidden SSIDs can still drop a `.nmconnection` in
`/etc/NetworkManager/system-connections/` or use `nmcli`. Deferred.

**Panel uses `Flickable` (not `ScrollView`).** Same reason as audio's
Apps tab and the bluetooth devices tab — `ScrollView`'s `parent.width`
doesn't propagate to its content under Quickshell (session-handoff
gotcha 5).

## What didn't ship

- **Hidden SSID entry.** See above.
- **Captive-portal helper.** `Networking.connectivity === Portal` is
  surfaced in the header ("Captive portal"), but Nirimaki does not
  launch a browser at the portal URL. Users open a browser themselves.
- **VPN management.** NM exposes VPN profiles; the panel currently
  ignores them. The wired tab cards the typed `WiredDevice` only.
  A VPN section is a natural follow-up but stays deferred.
- **Saved-network management without listing.** A user who forgot
  an SSID name but has the saved profile can't currently view their
  saved-only profiles — the panel only lists what's broadcasting now.
  NM stores profiles per-system; a "Saved profiles" sub-list pulled
  from `NMSettings` would close this gap. Deferred.
- **WPA-EAP / enterprise wifi UX.** `Network.connectWithSettings()`
  is the right entry point, but Nirimaki doesn't surface the cert /
  EAP-method picker yet. Open networks and PSK networks work today.
- **Static IPv4 / DNS / gateway editing.** `Network.nmSettings` exposes
  the full NM connection-settings tree (IPv4 method, addresses, DNS,
  search domains, MTU, route metrics, …). The panel currently only
  surfaces autoconnect + connect/forget — fields like a manual IPv4
  address or custom DNS servers are not editable in-panel. Escape
  hatches: `nm-connection-editor` (GTK GUI, ships with the
  `networkmanager` package), `nmtui`, or
  `nmcli connection modify <name> ipv4.method manual ipv4.addresses … ipv4.gateway … ipv4.dns …`.
  Building an in-panel editor (row-expansion with method dropdown +
  address/gateway/DNS forms) is a real UX effort and likely earns its
  own phase. Tracked for a future cleanup pass.
- **Per-row context menu (clone profile, set static IP, etc.).** All
  doable through NM's settings; not exposed here.

## Install requirements

- **New package**: `networkmanager`. Auto-installed by §2b on fresh
  installs; migration script `1779716834.sh` installs it on existing
  systems.
- **System enables**: `NetworkManager.service`. Same fresh-install
  and migration paths.
- **System disables**: `systemd-networkd.service` (and `.socket`).
  Same paths. Users who deliberately configured networkd can re-
  enable; the migration won't undo their manual change after the fact
  (it only runs once).
- **Dropped**: `impala` is no longer in default `packages.txt`. Users
  who want the TUI can still install it.

## Common ops

| Task                                | Command                                              |
|-------------------------------------|------------------------------------------------------|
| Open network panel                  | Settings menu → Setup → Network, or `quickshell ipc call shell summon network` |
| Open compact popover                | Left-click the network pill                          |
| Open panel from compact popover     | Click "manage" button at the bottom                  |
| Toggle wifi from anywhere           | Bar pill popover → "turn on" / "turn off"            |
| Scan for networks                   | Wi-Fi tab → "scan" in section header                 |
| Join an open network                | Wi-Fi tab → "connect" on its row                     |
| Join a secured network              | Wi-Fi tab → "password…" → type PSK → "connect"       |
| Disconnect from current SSID        | Wi-Fi tab → "disconnect" on the connected row        |
| Forget a saved profile              | Wi-Fi tab → "forget" on the saved row                |
| Toggle ethernet auto-connect        | Wired tab → "Connect automatically" toggle           |
| Dump live state for debugging       | `quickshell ipc call network dump`                   |
| Force a wifi scan from a script     | `quickshell ipc call network scan`                   |
