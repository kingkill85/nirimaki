# Phase L — UI kit foundation ✅

Group A of the [Quickshell migration plan](quickshell-migration-plan.md).
Added the input / control / display primitives the later groups
(AudioService panel, BluetoothService panel, NetworkService panel,
shell.json settings forms) need. Pure additions next to the existing
`BarPill` / `BarPopover` / `Popover*` family — no behaviour change to
any shipping plugin.

## What shipped

### 1. Theme tokens (Theme.qml)

A shared `control*` / `slider*` / `toggle*` / `dropdown*` / `tooltip*`
block, single source of truth for the kit. Reasoning per token:

| Token                       | Default | Where used                              |
|-----------------------------|---------|-----------------------------------------|
| `controlHeight`             | 32      | TextField, NumberField, Dropdown header, Button default |
| `controlPadX`               | 10      | Inner horizontal padding on every control |
| `controlBorderWidth`        | 1       | Default border                          |
| `controlFocusBorderWidth`   | 2       | Focused / open state                    |
| `controlSpacing`            | 8       | Between stacked controls                |
| `sliderTrackHeight`         | 4       | PanelSlider track                       |
| `sliderKnobSize`            | 14      | PanelSlider knob                        |
| `toggleTrackHeight`         | 22      | Toggle switch track                     |
| `toggleTrackWidth`          | 42      | Toggle switch track                     |
| `toggleKnobSize`            | 16      | Toggle switch knob                      |
| `toggleKnobInset`           | 3       | Knob inset from track edge              |
| `dropdownRowHeight`         | 30      | Dropdown / SearchableDropdown row       |
| `dropdownMaxRows`           | 8       | Before scrolling                        |
| `tooltipDelay`              | 600 ms  | Hover dwell before tooltip shows        |
| `tooltipPadX` / `tooltipPadY` | 8 / 4 | Tooltip padding                         |
| `tooltipFontPx`             | 11      | Tooltip text size (`fontPx - 2`)        |

### 2. Primitives

Added under `config/quickshell/` and registered in `qmldir`:

- **`Toggle`** — labeled switch row (title + optional description + pill
  switch). Stateless: emits `toggled(bool checked)`, caller flips
  `checked` in response. Animation on color + knob position. Used for
  adapter power, mute, future DnD / NightLight / StayAwake toggles.

- **`PanelSlider`** — horizontal slider with drag, click-to-set, and
  scroll-wheel adjust. `value` / `minimum` / `maximum` / `step` /
  `integer`. While dragging mutates a separate `liveValue` and emits
  `moved(v)` so callers can choose per-frame commit (Pipewire) vs
  release-only commit (HTTP-backed settings). Subtle knob scale on
  hover/drag.

- **`Dropdown`** — single-select dropdown. Header looks like a
  TextField (read-only + chevron); click opens an in-scene Rectangle
  list below. `model` + `textRole` + `valueRole` (read item properties)
  or pass plain strings with `textRole: ""`. Emits `selected(index, item)`.
  In-scene (no PopupWindow); fine inside panels, may clip inside small
  popovers — upgrade to PopupWindow then if needed.

- **`SearchableDropdown`** — Dropdown variant whose header is a TextField
  that filters the list by case-insensitive substring on `textRole`.
  Enter on header picks the first filter result. For ssid pickers,
  saved-network pickers, app launchers.

- **`TextField`** — single-line text input. Themed Rectangle chrome with
  focus border, placeholder, optional `leadingIcon` (Nerd-Font glyph).
  Same baseline as Toggle / Dropdown so settings forms read uniform.
  `accepted(text)` on Return, `editingFinished()` on focus loss.

- **`NumberField`** — extends TextField, clamps to `[minimum, maximum]`,
  rounds when `integer: true`, supports a display `suffix` (e.g. " s").
  Exposes typed `value: real` plus `valueCommitted(v)` emitted on
  editingFinished so transient mid-type digits don't write back.

- **`Tooltip`** — hover-delayed in-scene label. Position relative to a
  `target` Item: `below` (default) / `above` / `left` / `right`. For bar
  pills there's a complementary `BarPill.tooltipText` property — uses
  `PopupWindow` instead, so it can escape the 32-px bar vertical extent.

- **`Button`** — generic action button. Same `Variant` enum as
  `PopoverButton` (`Primary` / `Secondary` / `Urgent`) but defaults to
  `Theme.controlHeight` instead of `popoverButtonHeight`. Use anywhere
  outside a popover action row.

### 3. BarPill gains `tooltipText`

`BarPill` now has a `tooltipText: ""` property. When non-empty,
hovering for `Theme.tooltipDelay` ms (600 by default) pops a small
card below the bar with the text. The card is a `PopupWindow` anchored
to the pill's QSWindow, so it escapes the bar's 32-px extent cleanly.
No plugin uses this yet — added so future plugins can adopt it
incrementally.

## Design choices worth recording

**In-scene Dropdown vs PopupWindow.** The dropdown list is a plain
Rectangle stacked above siblings (z: 100), not a PopupWindow. Cheaper,
simpler. Works in any parent with room — panels and dialogs always
have room; popovers might clip. We accept the limitation for v1 and
revisit if a popover use case needs an escaping dropdown.

**Stateless Toggle.** `Toggle` emits `toggled(checked)` rather than
auto-flipping its own `checked` property. That way the caller stays
authoritative (especially important for service-backed toggles where
the source-of-truth is `AudioService.muted` or `NetworkService.wifiEnabled`,
not the widget's local state).

**Slider commits per-frame vs on release.** `PanelSlider` emits both
`moved(v)` (every change while dragging) and `released(v)` (on
mouse-up or wheel). Per-frame commits suit Pipewire (sink-volume
writes are cheap and instant); a saved-settings backend would
listen on `released` only.

**No Style.qml port.** Omarchy's `Style.qml` is 23 KB with a lot of
Hyprland-specific assumptions (focus styling, scaling tokens). We
cherry-picked just the tokens we'll use and added them to our
`Theme.qml` under labeled blocks. Easier to maintain, no dead code.

**Variant enum on Button mirrors PopoverButton.** Two near-identical
files instead of an inheritance chain. The mental model is clear
(Button = panel button, PopoverButton = popover action row), the
duplication is ~40 lines, and an inheritance chain in QML has its own
costs (enum re-export quirks).

## What didn't ship (deferred to Group B)

- **Dev-gallery plugin** — single overlay showing every primitive at
  once for visual QA. Needs `kind: overlay` + lazy summon, which
  arrives with the plugin-kinds work.

## Install requirements

None. All additions are pure QML in `config/quickshell/`, picked up by
quickshell reload. No new packages, no migration, no system changes.
