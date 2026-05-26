# Phase S — Monitor setup panel ✅

A graphical alternative to hand-editing `~/.config/niri/monitors.kdl`.
Sibling to the audio/bluetooth/network panels: lazy-summoned, lives
under Setup in the settings menu, writes monitors.kdl on Apply with a
confirm-or-revert safety net.

## What shipped

### 1. `MonitorService` singleton

`config/quickshell/MonitorService.qml` — wraps `niri msg --json
outputs`. Exposes:

| Property         | What                                                          |
|------------------|---------------------------------------------------------------|
| `outputs[]`      | One entry per connected output: `{id, connector, make, model, serial, modes[], currentMode, vrr/vrrSupported, scale, positionX, positionY, widthPx, heightPx, transform}` |
| `busy`           | `niri msg outputs` poll in flight                             |
| `applying`       | monitors.kdl write in flight (cleared after the post-write refresh) |
| `hasBackup`      | Pre-apply contents of monitors.kdl are cached and can be reverted to |

| Method                       | Effect                                              |
|------------------------------|-----------------------------------------------------|
| `refresh()`                  | re-poll outputs                                     |
| `snapshot()`                 | plain JS array of editable monitor objects          |
| `applyConfig(snap)`          | capture backup, render kdl, atomic-write monitors.kdl, schedule post-write refresh |
| `revert()`                   | restore the captured backup, schedule refresh; clears the backup so the same revert can't fire twice |
| `clearBackup()`              | drop the backup (user confirmed the new config is good) |
| `fmtRefresh(milliHz)`        | "60.000" — niri returns millihertz                  |
| `modeLabel(m)`               | "1920×1080 @ 60.000 Hz"                             |

Sequencing inside `applyConfig`:

1. `cat monitors.kdl` → `_backup` (so we can revert byte-for-byte
   even if the file has user-written comments we'd otherwise drop).
2. Render kdl from the snapshot.
3. Atomic write via `mktemp` + `mv` so a partial write never leaves
   monitors.kdl in a half-state.
4. niri's own file-watcher picks up the change and reloads.
5. 600ms later we `refresh()` so the panel sees the post-reload
   values.

The kdl writer fully regenerates monitors.kdl from the snapshot. V1
doesn't try to merge user comments — there's a header note in the
written file explaining this. The captured backup preserves the
*previous* file byte-for-byte, including any comments, so a revert
restores the user's hand-edits unchanged.

The EDID identifier used as the output key is `make + " " + model + "
" + serial` (matches the format niri's own outputs JSON and the seed
monitors.kdl use). Falls back to the connector name (`DP-3`) when
EDID fields are empty (uncommon).

### 2. monitors plugin — `kinds: ["panel"]`

`plugins/builtin/monitors/{plugin.json,Panel.qml}`. Two sections:

- **Drag-arrange canvas.** Computes a bounding box over every
  monitor's virtual position+size, scales the whole layout to fit
  inside the canvas with 24px padding. Each monitor renders as a
  rectangle proportional to its current mode; drag the rectangle to
  move it in virtual-pixel space. On drag-release the new position is
  snapped to the nearest 10-virtual-pixel multiple and written into
  the working snapshot.

  Selected output gets an accent-coloured border so the form below
  always lines up with the canvas selection. Pressing a tile sets
  selection.

- **Per-output form.** Three columns:
  1. **Output** — dropdown of every connected output (by connector
     name); selecting drives the canvas selection too.
  2. **Mode** — searchable dropdown of every mode the output
     advertises, formatted as `WxH @ R Hz` with a star ★ on the
     preferred mode.
  3. **Scale** — dropdown of 1.0× / 1.25× / 1.5× / 1.75× / 2.0×
     fractional scales. (Custom scale is deferred — power users edit
     monitors.kdl directly.)

- **Position / identifier read-out.** Live values pulled from the
  working snapshot. Identifier shows the canonical
  make/model/serial line that lands in monitors.kdl.

- **Footer.** *Cancel* re-pulls the snapshot (discarding edits) and
  closes. *Apply* triggers the confirm-or-revert flow below.

### 3. Confirm-or-revert overlay

A scrim+card inside the panel that pops up immediately on Apply with
a 10-second countdown. *Revert* rolls back to the backup. *Keep*
commits the new config (clears the backup so it can't be reverted
later). If the countdown reaches zero we revert automatically.

The scrim eats clicks (no fall-through to the panel under it) and the
panel's own Escape close is disabled while the confirm is open — the
only way past is one of the two buttons.

This is the GNOME-Display safety pattern, scoped to one plugin. If a
bad mode pick blanks a monitor for ≥10s the previous monitors.kdl
gets re-applied automatically.

### 4. Wiring

- `config/quickshell/settings-menu.json` — new entry
  `setup.monitors` under Setup → "Monitors", dispatching
  `{ type: "summon", id: "monitors" }`.
- `config/quickshell/i18n/{en,de}.json` — `monitors.*` keys for the
  panel labels + the menu entry.
- `config/quickshell/qmldir` — registers `MonitorService` as a
  singleton.

## Verification

- `quickshell ipc call shell listPlugins` — `monitors` shows up with
  `kinds: ["panel"]`, `installed: True`.
- `quickshell ipc call shell summon monitors ""` followed by
  `... hide monitors` round-trips cleanly with no log warnings.
- Opening Settings → Setup → Monitors summons the panel via the v2
  dispatcher.

## Out of scope / known limits

- **Hot-plug.** niri's event-stream has no per-output-changed event,
  so plugging in a new monitor while the panel is open doesn't
  auto-refresh the canvas. Workaround: close + reopen, or call
  `MonitorService.refresh()` from QML. Could be polled, but the
  steady-state cost outweighs the value.
- **Transform / rotation editor.** Snapshot carries `transform`
  through so a rotation set in monitors.kdl survives a round-trip,
  but the panel has no UI control for it yet. Add a fourth column
  with a rotation dropdown when there's demand.
- **Per-output disable / VRR toggle.** Same shape — snapshot has
  the field, no UI surface in V1.
- **Custom scale entry.** Dropdown-only for V1; arbitrary fractional
  scales (1.333…) are typed into monitors.kdl by hand.
- **Header-comment preservation.** The writer regenerates monitors.kdl
  from the snapshot — user comments above `output` blocks are
  replaced by the standard managed-by-Nirimaki header. The pre-apply
  backup preserves the *previous* contents byte-for-byte, so a
  revert restores hand-edits. A real merge would need a KDL parser,
  which is a separate effort.

## Files touched

- `config/quickshell/MonitorService.qml` (new)
- `config/quickshell/qmldir` (singleton registration)
- `config/quickshell/settings-menu.json` (Setup → Monitors entry)
- `config/quickshell/i18n/{en,de}.json` (monitors.* + menu label)
- `plugins/builtin/monitors/{plugin.json,Panel.qml}` (new)

## Common ops

| Task                            | Command                                                       |
|---------------------------------|---------------------------------------------------------------|
| Open the panel                  | Settings menu → Setup → Monitors, or `quickshell ipc call shell summon monitors ""` |
| Edit monitors.kdl by hand       | `nirimaki edit monitors` (still works; panel picks up changes on next open) |
| Force-revert from CLI           | Edit monitors.kdl directly — niri reloads on save             |
