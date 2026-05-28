# Phase T — VPN bar widget + service ✅

Aggregated VPN status in the bar. Two sources merge into one popover:
NetworkManager-managed profiles (OpenVPN / WireGuard / IPsec, auto-
discovered via `nmcli`) and custom providers declared in
`~/.config/nirimaki/vpns.d/<id>.json`. Setup UI is delegated to each
vendor's own tooling — we just show state + connect / disconnect /
launch-their-config-tool.

## What shipped

### 1. `VpnService` singleton

`config/quickshell/VpnService.qml` — single place every plugin reads
VPN state from. Aggregates:

- **NM VPNs** — `nmcli -t -f NAME,TYPE,STATE connection show`,
  filtered to `type ∈ {vpn, wireguard}`. Polled every 5 s; nmcli is
  ~5 ms a call, negligible.
- **Custom providers** — one JSON file per provider under
  `~/.config/nirimaki/vpns.d/<id>.json`:

  ```jsonc
  {
    "id":               "pia",
    "name":             "Private Internet Access",
    "icon":             "󰒃",
    "statusCmd":        ["piactl", "get", "connectionstate"],
    "statusOnPattern":  "^Connected$",
    "statusLabelCmd":   ["piactl", "get", "region"],   // optional
    "connectCmd":       ["piactl", "connect"],
    "disconnectCmd":    ["piactl", "disconnect"],
    "setupCmd":         ["pia-client"],                 // optional
    "pollSeconds":      5
  }
  ```

  `statusOnPattern` is a case-insensitive regex matched against the
  stdout of `statusCmd`. `statusLabelCmd` runs only while connected;
  its first line becomes the popover's secondary text and the bar
  pill label (e.g. "PIA · Frankfurt"). `setupCmd` is optional — if
  set, a gear button in the popover launches it.

| Property                | What                                          |
|-------------------------|-----------------------------------------------|
| `providers[]`           | unified `{id, kind, name, icon, connected, statusLabel, canSetup, _config}` list |
| `activeProviders[]`     | filtered `.connected` subset                  |

| Method                  | Effect                                        |
|-------------------------|-----------------------------------------------|
| `refresh()`             | re-poll NM + every custom provider            |
| `connect(id)`           | `nmcli connection up …` or `connectCmd`       |
| `disconnect(id)`        | `nmcli connection down …` or `disconnectCmd`  |
| `setup(id)`             | launches `nm-connection-editor` (NM) or the provider's `setupCmd` |

A single shared `Process` serialises every custom status poll so a
slow `statusLabelCmd` can't starve other providers. Polling cadence
is fixed at 5 s in V1 — the per-provider `pollSeconds` field in the
JSON is parsed but ignored; users typically have 1–3 providers so
the fixed cadence is fine.

### 2. `vpn` plugin

`plugins/builtin/vpn/{plugin.json,BarWidget.qml}`. Bar widget only —
no separate panel because management is delegated to vendor tools.

- **Bar pill**: shield icon, tinted accent when any provider is
  connected. When connected, the active provider names render
  alongside the icon: `"🛡 PIA · Frankfurt"` for one connection;
  `"🛡 PIA, Tailscale"` for multiple (drops the status-label suffix
  to keep the pill from running away in width).
- **Popover**: one row per provider — icon, name + status label,
  connect/disconnect button, gear button when `canSetup` is true.
  Empty state directs users at the sample configs.

NM-managed VPNs always show a gear button (it launches
`nm-connection-editor`). Custom providers show the gear only when
their JSON declares a `setupCmd`.

### 3. Sample provider configs

`config/nirimaki/vpns.d/{tailscale,pia,netextender}.json.sample`.
Cover the cases the user actually has + a likely-third (Tailscale).

- **Tailscale** — `tailscale status --json | jq .BackendState` for
  state, `.Self.DNSName` for the label. Connect / disconnect run
  `tailscale up/down`. Initial device auth still needs `tailscale
  up` from a terminal — the connect button can't drive the
  device-auth URL flow.
- **PIA** — pure `piactl` wrapper. Setup goes to the PIA GUI client
  (`pia-client`).
- **NetExtender** — `pgrep -x netExtender` is the state probe (the
  daemon is a single process); status label is the ppp0 IPv4.
  Connect calls a user-written wrapper that fills in credentials,
  e.g. via `secret-tool` from the GNOME keyring. The sample contains
  the wrapper template in its `_comment` block.

Drop the `.sample` extension to activate any of them; the loader
ignores anything that doesn't end in `.json`.

### 4. Wiring

- `config/quickshell/qmldir` — singleton registration.
- `~/.config/nirimaki/shell.json` — `vpn` entry added to
  `bar.right` between `network` and `system-stats`. New installs
  pick this up via `nirimaki-config-migrate`; existing installs
  need the entry added by hand (one-line edit).
- `config/quickshell/i18n/{en,de}.json` — `vpn.*` keys for the
  pill, popover, and row states.

## How a typical flow looks

```
nirimaki-config-migrate (or user edit) → shell.json includes `vpn`
                                       │
                                       ▼
Quickshell loads vpn/BarWidget.qml → renders bar pill
                                       │
                                       ▼
VpnService.refresh() → nmcli list  ─┐
                       cat *.json  ─┼─▶ providers[]
                       statusCmd   ─┘
                                       │
                       Bar pill subscribes to VpnService.activeProviders
                       Pill width / icon tint follow .connected state
                                       │
User clicks pill → BarPopover opens   ─▶  Row per provider; Connect/
                                          Disconnect / Configure
```

`Configure` per provider launches the vendor's own tool —
`nm-connection-editor` for NM-managed profiles, `pia-client` or
whatever for custom ones. Setup itself is intentionally out of scope
here; reinventing every vendor's auth/profile/region UX isn't worth it.

## Verification

- `quickshell ipc call shell ping` — clean.
- `quickshell ipc call shell listPlugins` — `vpn` shows up with
  `kinds: ["bar-widget"]`, `installed: True`, `mount: "bar.right"`.
- Bar pill renders (default empty when no providers configured);
  popover empty-state directs users at the sample configs.

## Out of scope / known limits

- **Tailscale's peer / exit-node model.** V1 treats Tailscale as a
  simple connect / disconnect provider via its CLI. Picking exit
  nodes, viewing peers, MagicDNS toggles — all done from `tailscale`
  CLI or its own UI. A richer dedicated Tailscale plugin is a
  natural follow-up phase.
- **Per-provider `pollSeconds`** in the JSON is parsed but ignored
  in V1; everything polls on the same 5 s tick.
- **Tunnel-establishment progress.** Connect/disconnect commands
  are fire-and-forget. The status label transitions from
  "Disconnected" through whatever interim states the provider
  reports to "Connected" on its own; no spinner / connecting UI.
- **Hidden-network / credential prompts for NM VPNs.** Resolved by
  the polkit-gnome agent autostarted from `default/niri/autostart.kdl`
  (see migration `1779963424.sh`). Activating a profile that needs
  interactive secrets now pops a password dialog instead of silently
  failing. The `secret-flags 0` / `secret-tool` workarounds still apply
  if you want non-interactive activation.

## Files this phase touched

- `config/quickshell/VpnService.qml` (new)
- `config/quickshell/qmldir` (singleton registration)
- `config/quickshell/i18n/{en,de}.json` (vpn.* keys)
- `plugins/builtin/vpn/{plugin.json,BarWidget.qml}` (new)
- `config/nirimaki/vpns.d/{tailscale,pia,netextender}.json.sample`
- `~/.config/nirimaki/shell.json` (user-side edit — vpn entry in bar.right)

## Common ops

| Task                                  | Command                                                       |
|---------------------------------------|---------------------------------------------------------------|
| Activate the Tailscale sample         | `cp config/nirimaki/vpns.d/tailscale.json.sample ~/.config/nirimaki/vpns.d/tailscale.json` |
| List discovered providers (debug)     | open the popover; the row count is the answer                 |
| Connect from CLI                      | `nmcli connection up <name>` or the provider's `connectCmd`   |
| Add a brand-new provider              | write `~/.config/nirimaki/vpns.d/<id>.json`; the FolderListModel picks it up at the next restart |
