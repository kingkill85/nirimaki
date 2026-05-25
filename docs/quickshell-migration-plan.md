# Quickshell migration — full plan

Inspired by `basecamp/omarchy#5856` ("Omarchy goes Quickshell"). This
doc captures the multi-phase plan that takes Nirimaki from "Quickshell
hosts a bar + a handful of overlays" to "Quickshell hosts the whole
desktop, including graphical replacements for the TUIs the bar
currently launches (wiremix / bluetui / etc.) plus full NetworkManager
wifi management".

## Status

- ✅ **Group A — UI kit foundation** (Phase L, `docs/phase-l-ui-kit.md`)
- ✅ **Group B — Plugin kinds + lifecycle** (Phase M, `docs/phase-m-plugin-kinds.md`)
- ✅ **Group C — shell.json migration** (Phase N, `docs/phase-n-shell-json.md`)
- ✅ **Group D — AudioService + audio panel** (Phase O, `docs/phase-o-audio.md`)
- 🔜 **Group E — BluetoothService + bluetooth panel** (Phase P, planned)
- 🔜 **Group F — NetworkService + network panel** (Phase Q, planned)
- 🔜 **Group G — Cleanup + polish** (Phase R, planned)

A picking-up-from-here cheat sheet — quickshell gotchas, key files,
new-session entry points — lives at
[`docs/session-handoff.md`](session-handoff.md).

## Goals

1. **Replace TUIs with native graphical control surfaces.** Audio mixer,
   bluetooth device manager, network connection manager — all summonable
   from the bar, the settings menu, or a keybind. Wiremix / bluetui /
   nmtui / nmcli stay available but become optional.
2. **Unified service singletons.** `AudioService`, `BluetoothService`,
   `NetworkService` — sibling to the existing `NiriService`. Plugins read
   from + write to these instead of shelling out per-plugin.
3. **Adopt Omarchy's positional layout config + plugin-kind lifecycle.**
   `~/.config/nirimaki/shell.json` owns the bar layout plus inline
   per-widget settings; `plugins.json` retires. Plugins declare `kinds`
   (`bar-widget`, `panel`, `overlay`, `menu`, `service`) and the loader
   summons non-bar kinds lazily.
4. **Standalone TUI replacements.** Each service-backed plugin ships
   *two* surfaces in one plugin:
   - `BarWidget.qml` — bar pill + compact popover (quick controls)
   - `Panel.qml` — full overlay with the comprehensive UI (opened from
     settings menu, a keybind, or `quickshell ipc call shell summon <id>`)
   Both share the service singleton, so the popover stays a lightweight
   view onto the same state the panel manipulates.

## The seven groups

Each group is a discrete shippable chunk. We land it, restart quickshell,
verify, then move on. Phase docs (`docs/phase-l..r-*.md`) document the
outcome of each group.

### Group A — UI kit foundation `→ phase-l-ui-kit.md`

The primitives every later group needs. Pure additions next to
`BarPill` / `BarPopover` / `Popover*`.

- `Toggle` — labeled switch row (wifi on/off, bt on/off, DnD, NightLight)
- `PanelSlider` — generalized slider; replaces audio's bespoke slider
- `Tooltip` + `tooltipText` on `BarPill` — discoverability
- `Dropdown` / `SearchableDropdown` — sink picker, ssid picker
- `TextField` / `NumberField` — wifi password, search fields, numeric entry
- `Button` (generic) — sibling to `PopoverButton`
- Theme tokens for control heights, slider geometry, etc.

Dev-gallery (a UI preview plugin) is deferred to Group B because it
needs the `overlay` kind to be implemented first.

### Group B — Plugin kinds + lifecycle `→ phase-m-plugin-kinds.md`

Refactor the plugin system to support panels / overlays / menus as
first-class lazy-loaded entries.

- Manifest schema v2: `kinds: []`, `entryPoints: {}`, kind-specific
  config blocks (e.g. `barWidget: {category, allowMultiple, schema}`)
- `Plugins.qml` learns `summon(id, payload)` / `hide(id)` / `toggle(id)`
  driven by IPC, menu entries, and keybinds
- Lazy load for `panel` / `overlay` / `menu` kinds (Loader instantiates
  on first summon; optional `keepLoaded: true` for state-heavy
  overlays like the image picker)
- IPC route: `quickshell ipc call shell summon <id> <json>`
- Migrate existing overlays (launcher, emoji-picker, clipboard-picker,
  theme-picker, power-menu, background-picker, language-picker) to
  `kind: overlay`, summon-on-demand
- Migrate `settings-menu` to `kind: menu`
- Existing bar widgets default to `kind: bar-widget`, zero behavior change
- **Dev-gallery plugin** ships here as the first new `kind: overlay`
  consumer — single overlay showing every primitive at once, summoned
  with `quickshell ipc call shell summon nirimaki.dev-gallery`

### Group C — shell.json migration `→ phase-n-shell-json.md`

Replace `plugins.json` with positional layout + inline settings.

- Schema: `{version, bar:{position, layout:{left,center,right}: [{id, ...settings}]}, plugins:[]}`
- `Config.qml` singleton — owns shell.json, `FileView`-watched
- `setting(key, fallback)` helper on plugin base — reads inline settings
- Manifest declares settings schema (`schema: [{key, type, label, default}]`)
  for a future bar-settings visual editor
- One-shot migrator: existing `plugins.json` → `shell.json` on first run,
  backup old file to `plugins.json.pre-migration`
- `allowMultiple: true` support — e.g. two clock entries with different
  timezones

### Group D — AudioService + audio plugin `→ phase-o-audio.md`

Drops wiremix as required tooling.

- `AudioService.qml` singleton — wraps `Quickshell.Services.Pipewire`,
  exposes `defaultSink`, `defaultSource`, `sinks[]`, `sources[]`,
  `streams[]` (per-app), setters for default / volume / mute / app-volume
- Audio plugin's `BarWidget.qml` — pill + compact popover (current size,
  but using `AudioService` instead of inline Pipewire wiring)
- Audio plugin's `Panel.qml` — full mixer overlay:
  - Default sink section (name + slider + mute)
  - Sink list (radio buttons + per-sink mute + per-sink volume)
  - Per-app stream list (slider + mute per stream)
  - Source / input section (input device picker + monitor meter + mute)
- Settings menu → "Audio mixer" entry → summons panel
- Optional keybind (e.g. Mod+Shift+A) → summons panel
- Right-click on bar pill → summons panel (was: launch wiremix). Wiremix
  package becomes optional.

### Group E — BluetoothService + bluetooth plugin `→ phase-p-bluetooth.md`

Drops bluetui as required tooling.

- `BluetoothService.qml` singleton — BlueZ DBus wrapper. Exposes
  `adapter` (powered, discoverable, discovering), `devices[]` (paired,
  connected, RSSI, icon, type, mac, name). Methods: `setPowered`,
  `scan(start|stop)`, `connect`, `disconnect`, `pair`, `trust`, `remove`
- Bluetooth plugin's `BarWidget.qml` — pill + compact popover (power
  toggle, 2-3 connected device summary, "open manager" button)
- Bluetooth plugin's `Panel.qml` — full device manager:
  - Adapter section (power, discoverable, discovering toggles)
  - Paired devices list (icon + name + state + per-device actions)
  - Available devices (with scan toggle, RSSI bars, pair button)
  - Per-device detail (when expanded): trust, forget, audio routing
- Settings menu → "Bluetooth" entry → summons panel
- Right-click on bar pill → summons panel. Bluetui package becomes optional.

### Group F — NetworkService + network plugin `→ phase-q-network.md`

Full wifi / connection management. Commits to NetworkManager dependency.

- `install.sh`: add `networkmanager` package, enable + start `NetworkManager.service`,
  write migration that disables systemd-networkd cleanly (or coexists
  if the user had it manually configured)
- Migration script for existing users on networkd:
  `migrations/<ts>-networkmanager.sh` detects systemd-networkd, prompts,
  switches over
- `NetworkService.qml` singleton — NetworkManager DBus. Exposes
  `primaryConnection`, `devices[]` (eth + wifi + vpn), `accessPoints[]`
  (ssid, security, signal, saved), `connections[]` (saved profiles).
  Methods: `scan`, `activate(connection)`, `deactivate(connection)`,
  `addAndActivate(ssid, password)`, `forget(connection)`
- Network plugin's `BarWidget.qml` — pill + compact popover (status
  icon, signal bars when wifi, primary connection name, scan toggle,
  top 3 networks by signal)
- Network plugin's `Panel.qml` — full manager:
  - Wifi section: ssid list with signal/security/saved markers, connect
    flow (password prompt for new networks, hidden-ssid entry, captive-
    portal detection)
  - Saved connections section: rename, auto-connect toggle, forget
  - Ethernet section: per-interface state, MTU
  - VPN section: list of saved VPN profiles, activate/deactivate
  - Current connection details: IP, gateway, DNS, link speed
- Settings menu → "Network" entry → summons panel
- Right-click on bar pill → summons panel
- Drop `ip route` + `/sys/class/net` polling

### Group G — Cleanup + polish `→ phase-r-cleanup.md`

Final pass once D / E / F are in.

- Remove `bin/` helpers that no longer make sense (audio-output-volume
  stays for keybind use — it acts on `AudioService` via IPC now)
- Audit right-click handlers across plugins — every service-backed bar
  pill right-clicks into its panel
- Update CLAUDE.md primitives table + add a "service singletons" section
- Migration: `migrations/<ts>-networkmanager.sh` for existing-install users
- Re-test settings menu, every popover, every panel summon path
- Decide on package removal: keep wiremix/bluetui as optional packages
  for power users? Or drop from `packages.txt` entirely?

## Sequencing

```
A → B → C   foundation (must be in order)
C → D       audio first service
D → E       bluetooth second
E → F       network last (biggest, riskiest)
G           continuous cleanup, finalised after F
```

Each service group depends on Group A (UI kit) and Group B (plugin
kinds, so the Panel surface can be lazy-summoned). Group C (shell.json)
must land before D-F so per-widget settings (default volume profile,
auto-connect wifi networks, paired-device pinning) have a home.

## Architecture decision: two surfaces per service plugin

One plugin (`audio`, `bluetooth`, `network`) ships:

- `BarWidget.qml` — `kind: bar-widget`, the bar pill + compact popover
- `Panel.qml` — `kind: panel`, the full standalone overlay

Manifest:

```jsonc
{
  "id": "nirimaki.audio",
  "kinds": ["bar-widget", "panel"],
  "entryPoints": {
    "barWidget": "BarWidget.qml",
    "panel":     "Panel.qml"
  },
  "barWidget": { "displayName": "Audio", "category": "Audio" },
  "panel":     { "displayName": "Audio mixer", "ipcId": "audio" }
}
```

Both surfaces import the same singleton (`AudioService`), so the
popover is a lightweight live view onto the same state the panel
manipulates. Panel summoned via:

- `quickshell ipc call shell summon nirimaki.audio panel`
- Settings menu entry pointing at the same IPC call
- A keybind that does the same
- Right-click on the bar pill (mirrors how audio's right-click currently
  launches wiremix)

## Files this plan will touch

Roughly:

- `config/quickshell/` — new primitives (Group A), new services (D-F),
  updated `Plugins.qml` (Group B), new `Config.qml` (Group C)
- `plugins/builtin/audio/` — split into `BarWidget.qml` + `Panel.qml` (D)
- `plugins/builtin/bluetooth/` — same shape (E)
- `plugins/builtin/network/` — same shape (F)
- `plugins/builtin/dev-gallery/` — new in Group B
- `plugins/builtin/*/plugin.json` → `manifest.json` schema update (Group B)
- `~/.config/nirimaki/plugins.json` → `shell.json` migration (Group C)
- `install/` — NetworkManager dependency, service enable (Group F)
- `migrations/` — one-shot scripts for shell.json + NetworkManager (C, F)
- `docs/phase-l..r-*.md` — outcome docs per group

## Out of scope (for now)

These came up while comparing to Omarchy but stay deferred:

- Multiple bars per session / vertical bars (their `Bar` plugin
  supports both axes; we stay top-horizontal until there's demand)
- Touch-screen virtual keyboard (`KeyboardPanel`)
- Bar settings *visual editor* (drag-drop reorder + per-widget setting
  forms) — schema lands in Group C, the editor is a follow-up after F
- NightLight / DnD / StayAwake / Reminders / Polkit plugins — separate
  features, each becomes its own small phase doc after the core
  migration finishes
- Indicators cluster widget (the hover-reveal status-icon cluster
  Omarchy uses) — nice cleanup, defer until we have DnD/NightLight
  plugins to populate it
