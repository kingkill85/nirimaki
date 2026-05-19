## Step 26 — Zen Browser window rule (un-numbered fix)

**Goal:** make Zen Browser tile cleanly into a niri column on launch. Without
this, Zen committed its first frame at the size it remembered from a previous
session — often much larger than the column — and only snapped to the column
size after the next compositor event.

In `~/.config/niri/config.kdl`, add a `window-rule` block:

```kdl
window-rule {
    match app-id=r#"^zen$"#
    tiled-state true
    clip-to-geometry true
}
```

`tiled-state true` tells Zen (via the xdg-toplevel state) that it is tiled,
so it drops its CSD shadow and rounded corners. `clip-to-geometry true`
clamps any residual overflow at the niri side.

---

## Step 27 — OSD bezel for volume / mute (Omarchy port)

**Goal:** pop a small bottom-centre bezel when the user changes volume,
mutes the speakers, or mutes the mic. Match Omarchy's quickshell OSD as
closely as possible.

**Design:** **IPC-driven**, not Pipewire-reactive. External wrapper scripts
adjust state via `wpctl` and then notify the shell via
`quickshell ipc call -- osd show '<json>'`. This matches Omarchy's pattern
in `basecamp/omarchy` on the in-progress `omarchy-shell` branch
(`shell/plugins/osd/Osd.qml` + `bin/omarchy-osd` + `bin/omarchy-audio-*`).

**Files:**

- `~/.config/quickshell/Osd.qml` — port of `shell/plugins/osd/Osd.qml`.
  Single `IpcHandler { target: "osd" }` at the root; per-screen
  `PanelWindow` via `Variants`. Card: 269×68 px, bottom-anchored with
  `bottomMargin: 67`. Hide timer 1200 ms. `Color.alpha(c,a)` upstream →
  `Qt.rgba(c.r, c.g, c.b, a)`; `qs.Commons` colors → `Theme` singleton;
  `JetBrainsMono Nerd Font` → `Theme.iconFamily` (NL variant in this shell).
- `~/.config/quickshell/qmldir` — add `Osd 1.0 Osd.qml`.
- `~/.config/quickshell/shell.qml` — instantiate a single `Osd {}`
  (the IpcHandler must register once globally; per-screen window comes
  from the inner `Variants`).

**Helper scripts (chmod 755) in `~/.local/bin/`** — ports of Omarchy's
`bin/omarchy-osd` and `bin/omarchy-audio-*`, renamed `qs-*`:

- `qs-osd` — `-i <icon> -p <progress> -m <message>` → builds JSON
  payload with python3 (for safe message escaping) and calls
  `quickshell ipc call -- osd show "$payload"`.
- `qs-audio-output-volume <raise|lower|mute-toggle|±N>` — calls `wpctl`,
  reads back percent + MUTED state, then `qs-osd -i volume-{high,muted}
  -p <percent>`. Includes the same 250 ms debounce on `mute-toggle` that
  Omarchy uses (some media keyboards double-fire).
- `qs-audio-input-mute` — toggle `@DEFAULT_AUDIO_SOURCE@`, then
  `qs-osd -i microphone[-muted] -m "Microphone {on,muted}"`.

**Gotcha — `quickshell ipc call` and `--`:**

`quickshell ipc call osd show '<payload>'` is silently rejected:

```
The following argument was not expected: {"icon":"volume-high",...}
```

`show` collides with the sibling `quickshell ipc show` subcommand in the
CLI11 parser. Insert `--` before the target:

```sh
quickshell ipc call -- osd show "$payload"
```

This is documented in `qs-osd` so future-me doesn't repeat the diagnosis.

**Niri keybind changes** in `~/.config/niri/config.kdl`:

```kdl
XF86AudioRaiseVolume allow-when-locked=true { spawn "/home/michael/.local/bin/qs-audio-output-volume" "raise"; }
XF86AudioLowerVolume allow-when-locked=true { spawn "/home/michael/.local/bin/qs-audio-output-volume" "lower"; }
XF86AudioMute        allow-when-locked=true { spawn "/home/michael/.local/bin/qs-audio-output-volume" "mute-toggle"; }
XF86AudioMicMute     allow-when-locked=true { spawn "/home/michael/.local/bin/qs-audio-input-mute"; }
```

(Replaces the default direct `wpctl` invocations — they bypassed the OSD.)

**Gotcha — niri PATH does NOT include `~/.local/bin`:**

niri inherits PATH from the login session, which on this Arch box is
`/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl`
— no `~/.local/bin`. A bare `spawn "qs-audio-output-volume" "raise"` fails
silently (no audible volume change, no OSD). Two ways to fix:

- **Absolute path in the keybind** (what's used above). Local to this
  config, no global PATH change.
- Add `environment { PATH "$HOME/.local/bin:$PATH"; }` at the top of
  niri's config — affects every spawn. Deferred until we have more than
  a handful of `qs-*` binds.

Diagnose via `cat /proc/$(pgrep -x niri)/environ | tr '\0' '\n' | grep PATH`.

**Same gotcha bites a second time inside the scripts.** The wrapper scripts
themselves call other wrappers (e.g. `qs-audio-output-volume` calls
`qs-osd` at the end). Those nested lookups also fail under niri's PATH
because the spawned-script inherits niri's PATH. Each `qs-*` script
exports PATH explicitly at the top:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Symptom of forgetting this: volume changes audibly (the first wpctl call
runs because wpctl lives in `/usr/bin`), but no OSD bezel appears (the
`qs-osd` lookup fails).

**Brightness:** skipped for now — this is a 3×DP desktop with no laptop
backlight, so `XF86MonBrightness*` keys are effectively no-ops until the
`ddcutil` Phase C step adds external-monitor brightness control. The OSD
already supports `-i brightness` payloads when that lands.

**Verification:**

```sh
quickshell ipc show         # should list `target osd` with 4 functions
qs-osd -i volume-high -p 42
qs-audio-output-volume +1 && qs-audio-output-volume -1
# (and watch the bottom-center bezel appear on every monitor for 1.2 s)
niri validate
```

---

## Step 28 — Clipboard history picker (cliphist + Omarchy port)

**Goal:** Walker-style overlay listing recent clipboard entries, fuzzy
search, click / Enter to copy back + paste into the focused window.
Matches Omarchy's `shell/plugins/clipboard-picker/ClipboardPicker.qml`
visually and behaviourally; backend swapped to Arch-native tools.

**Packages:**

```sh
sudo pacman -S --needed cliphist wtype
```

`wl-clipboard` was installed in Step 17. `cliphist` is the Wayland-native
clipboard manager (extra repo); `wtype` lets the picker synthesise a
`Shift+Insert` keystroke so the selected entry pastes directly into the
focused window rather than just landing on the clipboard.

**Cliphist daemon at session start** in `~/.config/niri/config.kdl`:

```kdl
spawn-sh-at-startup "wl-paste --watch cliphist store"
```

`wl-paste --watch` runs forever, calling `cliphist store` for every new
clipboard selection. Entries go to `~/.cache/cliphist/db`.

**Quickshell port:** `~/.config/quickshell/ClipboardPicker.qml` ports
Omarchy's QML (registered in `qmldir`, added to `shell.qml` as
`ClipboardPicker {}`). Adaptations:

- Backend: `elephant query --json clipboard;;100` → `cliphist list`
  (line-based, `<id>\t<preview>` format). Parsed into the same
  `{ identifier, preview, preview_type }` shape the picker expects.
- Activation: `elephant activate clipboard;<id>;copy` → `cliphist decode
  '<id>' | wl-copy && sleep 0.05 && wtype -M shift -P Insert -p Insert
  -m shift`. The wtype step pastes into the focused window; the
  `|| true` guard means it's a no-op when wtype isn't installed (entry
  still lands on the clipboard).
- Theming: `qs.Commons` `Color.menu.{background,text,selected}` /
  `Style.cornerRadius` / `OMARCHY_MENU_FONT` env → `Theme.bg` / `Theme.fg`
  / `Theme.accent` / `Theme.radius` / `Theme.monoFamily`.
- Removed: omarchyPath, manifest, pluginRegistry properties
  (Omarchy-plugin-system specific).
- Removed: image preview pane via `Image { source: file://... }` —
  cliphist doesn't surface a decoded file path, only an "[[ binary
  data N <type> bytes ]]" placeholder. Image entries show as italic
  "Image" rows; selecting them still pastes the binary correctly.
- Removed: password masking (`meta === "password"`) — cliphist has no
  password-type metadata.

**Niri keybind**:

```kdl
Mod+Y hotkey-overlay-title="Clipboard history" {
    spawn "quickshell" "ipc" "call" "--" "clipboard-picker" "toggle";
}
```

Used `Mod+Y` ("yank") because:
- `Mod+V` is `toggle-window-floating` (niri default — keep).
- `Mod+Period` is `expel-window-from-column` (niri default — keep).

`--` separator is required after `call` for the same CLI11 reason
documented in Step 27.

**Verification:**

```sh
pgrep -af 'wl-paste --watch cliphist'   # daemon running
echo "hello" | wl-copy
echo "world" | wl-copy
cliphist list                            # should show both
```

Press `Mod+Y` → picker overlay → arrow keys / type to filter / Enter to
paste. After restarting quickshell (`quickshell kill` then `quickshell
--daemonize` from autostart), the IPC target `clipboard-picker` appears
in `quickshell ipc show`.

---

## Step 29 — Power menu (Lock / Suspend / Logout / Restart / Shutdown)

**Goal:** Replace niri's bare quit-confirmation dialog (the `quit` action
on `Mod+Shift+E`) with a styled walker-style menu offering the standard
set of session actions.

**Scope note:** Omarchy ships a much bigger
`shell/plugins/menu/Menu.qml` (~36 KB) — a generic JSONC-driven command
menu with drilldowns, providers, and `when` gates. Their power actions
live under the `system.*` namespace in
`default/omarchy/omarchy-menu.jsonc`. Porting the full menu system is
its own multi-step project; for this Phase C item we ship a focused
power-only popup visually styled the same way (300 px card,
JetBrainsMono Nerd Font, identical icons cribbed from their JSONC). If
we later want the full Omarchy menu UX, that's a follow-up.

**File:** `~/.config/quickshell/PowerMenu.qml`. Same pattern as the
Launcher / ClipboardPicker:

- `PanelWindow` overlay, layer-shell exclusive keyboard focus.
- 300 × auto-height card centred on the screen.
- Header line acts as the search box; arrow keys / Enter activate.
- 5 hardcoded actions, icons matching Omarchy's `system.*`:
  - `󰌾` Lock     — `swaylock`
  - `󰒲` Suspend  — `systemctl suspend`
  - `󰍃` Logout   — `niri msg action quit --skip-confirmation`
  - `󰜉` Restart  — `systemctl reboot`
  - `󰐥` Shutdown — `systemctl poweroff`
- IPC: `target: "power-menu"`, functions `summon` / `hide` / `toggle` /
  `ping`. Same shape as ClipboardPicker.
- Activation uses `Quickshell.execDetached(cmd)` with an argv array
  (avoids shell quoting).

Registered in `qmldir`, instantiated once in `shell.qml`.

**Niri keybind change** in `~/.config/niri/config.kdl`:

```kdl
Mod+Shift+E hotkey-overlay-title="Power menu" {
    spawn "quickshell" "ipc" "call" "--" "power-menu" "toggle";
}
Ctrl+Alt+Delete { quit; }
```

`Ctrl+Alt+Delete` is kept on the niri built-in confirmation dialog as a
fallback in case the shell isn't running.

**Hibernate:** skipped. Omarchy gates it behind
`omarchy-hibernation-available`; on this 3×DP desktop with no swap
configured for hibernation it would just fail. Add a sixth action later
if hibernation gets set up.

**Verification:**

```sh
quickshell ipc show | grep -A1 power-menu   # target + 4 functions
```

Press `Mod+Shift+E` → menu pops. Esc / click-outside dismisses without
side-effects. Navigate with Up / Down or type to filter; Enter activates.

---

## Step 30 — Pacman update-count widget

**Goal:** small bar widget showing the number of pending pacman updates.
Click to run `paru -Syu` in a floating kitty TUI. Hidden when zero
updates pending.

**No Omarchy upstream:** their `shell/plugins/bar/widgets/` tree doesn't
include an updates widget, so this is a custom port styled to match the
existing bar widgets (Bluetooth / Network / SystemStats — same pill,
icon glyph from JetBrainsMono Nerd Font, click → floating kitty).

**File:** `~/.config/quickshell/Updates.qml`. Polls
`checkupdates 2>/dev/null | wc -l` every 10 minutes (the cadence
pacman-contrib documents for `checkupdates` — uses a temp DB so it
neither needs root nor pounds mirrors). Stores the count and:

- Renders `󰚰 <count>` pill when `count > 0`.
- Sets `implicitWidth: 0` and `visible: false` when `count === 0` so the
  widget collapses out of the bar layout entirely.
- On click, launches `paru -Syu` via `NiriService.launchTui("updates",
  "bash", "-lc", "paru -Syu; … read")`. The shared `^tui-` window rule
  floats the kitty at 1000×640. Re-polls immediately after click via
  `Qt.callLater(refresh)` so the count reflects the new state once
  paru finishes.

Registered in `qmldir`. Placed between `Network` and `SystemStats` in
`Bar.qml`.

**Exit-code caveats:** `checkupdates` returns
- `0` with stdout = N package lines when there are N updates,
- `2` with empty stdout when nothing needs upgrading,
- `1` on error (lock file present, network failure).
We just count stdout lines via `wc -l` so any error path naturally
collapses to `count == 0` and the widget hides.

**Verification:**

```sh
checkupdates 2>/dev/null | wc -l    # should match the bar pill
```

If the bar shows `󰚰 N` matching the command's output, the widget is
live. Click it → kitty floats with paru -Syu running.

---

## Step 30b — Update widget: shared singleton + pacman-log inotify + center placement

**Symptoms found after Step 30:**
- Widget only appeared on one monitor (whichever Bar happened to win the
  pacman-contrib lock race — three simultaneous `checkupdates` from
  three Bars).
- Count stayed stale after `paru -Syu` finished: the immediate
  `Qt.callLater(refresh)` ran *before* the actual upgrade transaction.
- User noted Omarchy puts updates in the bar centre, not the right cluster.

**Fixes:**

- New `UpdatesService.qml` singleton owns the single `checkupdates`
  Process. `Updates.qml` widgets in each Bar just read `count`/`any` from
  it. Eliminates the lock race.
- The singleton also runs a `FileView { path: "/var/log/pacman.log";
  watchChanges: true }` and calls `refresh()` on every change. Covers
  both widget-click and external upgrades.
- `Bar.qml` `anchors.centerIn` Calendar is wrapped in a `Row` so it can
  sit alongside `Weather` and `Updates`, matching Omarchy waybar's
  modules-center order (clock → weather → update).
- Click handler no longer does the eager `Qt.callLater(refresh)` — the
  pacman-log watch handles it deterministically.

**Icon:** kept as `󰚰` (nf-md-package_up) per user preference. Omarchy
waybar uses `` (nf-cod-package) but the user wanted the larger MDI
glyph back.

---

## Step 31 — Weather widget + flyout

**Goal:** bar pill showing current icon + temp; click opens a popup
matching Omarchy's weatherFlyout (big icon + temp on the left, location
+ FEELS / WIND / HUMID on the right, 3-day forecast row underneath).

**Position:** centre cluster, between `Calendar` and `Updates` — same
order Omarchy waybar uses for `modules-center` (clock → weather →
update).

**Data flow** (simpler than Omarchy's three-source flyout):
- Location: one `curl https://get.geojs.io/v1/ip/geo.json` on first
  open / startup → `{ latitude, longitude, city }`. ipapi.co paywalls
  free traffic now; ip-api.com only serves HTTPS to paying customers;
  geojs.io is HTTPS, free, no auth.
- Forecast: one
  `curl https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…
  &current=temperature_2m,apparent_temperature,relative_humidity_2m,
  weather_code,wind_speed_10m
  &daily=weather_code,temperature_2m_max,temperature_2m_min
  &forecast_days=4&timezone=auto` every 15 min, plus on popup open and
  middle-click of the pill.
- Locale-driven units: `en_US` → Fahrenheit/mph, everyone else
  Celsius/km/h. Override via the `useImperial` property.

**Icon map:** Open-Meteo WMO weather code → `nf-md-weather_*` glyph
(`iconForCode` function). Simpler than Omarchy's wttr.in code map; the
two coding schemes are not interchangeable.

**File:** `~/.config/quickshell/Weather.qml`. Registered in `qmldir`,
inserted into the centre `Row` in `Bar.qml` between `Calendar` and
`Updates`.

**Skipped vs Omarchy upstream:**
- No `weather.sh` Omarchy helper — it injects extra fields that we
  derive directly from the open-meteo payload.
- No PopupCard / WidgetButton wrappers — replaced with a plain
  `PopupWindow` matching this shell's existing Network/Bluetooth popup
  pattern.
- No fallback to wttr.in 3-day forecast — Open-Meteo covers it.

**Verification:**

```sh
curl -fsS --max-time 5 'https://get.geojs.io/v1/ip/geo.json' | head -1
curl -fsS --max-time 5 \
  "https://api.open-meteo.com/v1/forecast?latitude=50.7803&longitude=12.7107&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4&timezone=auto" | head -1
```

Pill should appear in the bar centre after both calls return; clicking
opens the flyout.

---

## Step 31b — Tray widget fixes (clicks + platform menus)

**Symptoms found while exercising the existing Tray widget:**
- The Remmina (Ayatana) tray icon showed but every click was a no-op:
  left-click didn't activate, right-click didn't open the menu.

**Root causes:**

1. **Wrong API signatures.** The original `Tray.qml` (Step 12) called
   `modelData.activate(x, y)` and `modelData.secondaryActivate(x, y)`,
   but Quickshell 0.3.0's `SystemTrayItem.activate()` /
   `secondaryActivate()` take **no** arguments — the doc page is
   explicit. The extra args either threw silently or no-op'd.
2. **Wrong menu API.** `cell.modelData.display(QsWindow.window, …)` used
   an undefined `QsWindow.window` attached property; nothing surfaced.
   For an SNI menu, the right path is the declarative
   `QsMenuAnchor { menu: modelData.menu; anchor.item: cell }`.
3. **Platform menus disabled.** Even with the correct anchor, the menu
   still didn't appear. The .qslog file revealed:

   ```
   Cannot call QsMenuAnchor.open() as quickshell was not started in
   QApplication mode. To use platform menus, add
   `//@ pragma UseQApplication` to the top of your root QML file.
   ```

   Quickshell defaults to QGuiApplication, which can't host platform
   menus. The pragma flips it to QApplication and unlocks them.

**Fixes:**

- `~/.config/quickshell/shell.qml` first line:
  ```qml
  //@ pragma UseQApplication
  ```
- `Tray.qml`:
  - Drop x/y from `activate()` / `secondaryActivate()`.
  - Replace `display()` with `QsMenuAnchor { menu: cell.modelData.menu;
    anchor.item: cell; anchor.rect.y: cell.height }` so the menu opens
    just below the cell.
  - Add a letter-placeholder Text (first letter of `title || id`) so
    icons that fail to resolve still leave a visible/clickable target.
  - Accept and propagate `barWindow` from `Bar.qml`, even though
    `anchor.item` doesn't strictly need it — useful for any future
    popup that does.

**Diagnostic note:** Quickshell's QML `console.log` and internal warnings
go to the per-instance binary log at
`/run/user/<uid>/quickshell/by-id/<id>/log.qslog`. Use `strings` to
grep that file when nothing surfaces to stdout — that's where the
QApplication warning was hiding. Saved as a feedback memory.

---

## Step 32 — Emoji picker (Omarchy port)

**Goal:** Walker-style grid of every emoji, fuzzy-searchable by keyword,
Enter pastes the chosen emoji into the focused app (plus `wl-copy` so
it's also on the clipboard).

**Files:**

- `~/.config/quickshell/EmojiPicker.qml` — port of Omarchy's
  `shell/plugins/emoji-picker/EmojiPicker.qml` (omarchy-shell branch).
- `~/.config/quickshell/emojis.json` — Omarchy's emoji database, 1870
  entries shaped `{ e: "<emoji>", k: "<space-separated keywords>" }`.
  Downloaded once from the omarchy-shell branch:

  ```sh
  curl -fsS \
    https://raw.githubusercontent.com/basecamp/omarchy/omarchy-shell/shell/plugins/emoji-picker/emojis.json \
    -o ~/.config/quickshell/emojis.json
  ```

- `~/.config/quickshell/qmldir` — `EmojiPicker 1.0 EmojiPicker.qml`.
- `~/.config/quickshell/shell.qml` — instantiate one `EmojiPicker {}`.

**Pattern:** identical to ClipboardPicker (overlay PanelWindow,
exclusive keyboard focus, walker-style search header, key catcher with
arrow / page / Enter / Esc / Backspace handlers). The list-view is
swapped for a `GridView` with 8 columns × ~10 visible rows of 44 × 44
cells, since emoji are wider than text rows. Activation:

```bash
wl-copy '<emoji>' && sleep 0.05 && wtype '<emoji>'
```

(`wtype` was installed for the clipboard step; same `Shift+Insert`-ish
pattern.)

**Adaptations from upstream:**

- `qs.Commons` (`Color.menu.*`, `Style.cornerRadius`,
  `OMARCHY_MENU_FONT`) → `Theme.qml` singleton.
- Dropped `omarchyPath`, `shell`, `manifest`, `pluginRegistry` plugin-
  framework properties; `FileView.path` hardcoded to
  `~/.config/quickshell/emojis.json`.
- Removed the upstream `dismiss()` callback into the host shell — our
  setup has no plugin host, so `closePicker()` is enough.

**Niri keybind:**

```kdl
Mod+E hotkey-overlay-title="Emoji picker" {
    spawn "quickshell" "ipc" "call" "--" "emoji-picker" "toggle";
}
```

`Mod+.` is the Windows / GNOME convention but it's already
`expel-window-from-column` in niri's defaults. `Mod+E` is free and
mnemonic.

**Verification:**

```sh
quickshell ipc show | grep emoji-picker   # target + 4 functions
```

Press `Mod+E` → grid opens; type "rocket" → emoji filters; Enter pastes
🚀 into the focused window.

---

## Step 33 — Screen recording (wf-recorder) + indicator

**Goal:** keybind to start/stop a region screen-recording, with a
pulsing red bar widget while it runs.

**Package:** `wf-recorder` (extra). Slurp + wl-clipboard from Step 21
already cover the region picker and clipboard pipeline.

**Helper script:** `~/.local/bin/qs-screenrecord` — toggles wf-recorder.
First press picks a region via `slurp -o -d`, starts wf-recorder in the
background writing to `$XDG_VIDEOS_DIR/screenrecording-<date>.mp4`,
stashes the filename in `$XDG_RUNTIME_DIR/qs-screenrecord.last`, fires a
notify-send. Second press sends `SIGINT` to wf-recorder (the only signal
that lets it finalize the MP4 cleanly), waits up to 5 s, falls back to
`SIGKILL` if it didn't finish, and notifies the saved file.

Why not gpu-screen-recorder (what Omarchy ships): Omarchy's flow
(`bin/omarchy-capture-screenrecording`) is hyprctl-bound (monitor
geometry, focused workspace), pulls in webcam overlay via ffplay,
mixes desktop + microphone audio with PipeWire, then post-processes the
file (loudnorm, warm-up trim). Porting all that to niri is its own
project. wf-recorder is the wlroots-native, single-binary equivalent
and the Phase C list called for it explicitly.

**QML widget:** `~/.config/quickshell/ScreenRecord.qml`. Polls
`pgrep -x wf-recorder` every 2 s; renders nothing when idle. While
recording shows `󰻂` (nf-md-record_rec) in `Theme.urgent`, pulsing
opacity 1.0 ↔ 0.55 every 700 ms. Click on the pill spawns the same
`qs-screenrecord` script — clicking the widget acts as the stop key.

Registered in `qmldir`, slotted into the bar between `Media` and
`Tray` in `Bar.qml`.

**Niri keybind:**

```kdl
Mod+Alt+R allow-when-locked=false hotkey-overlay-title="Toggle screen recording (wf-recorder)" {
    spawn "/home/michael/.local/bin/qs-screenrecord";
}
```

`Mod+Shift+R` would have matched the `Mod+Shift+S` (screenshot) cluster
but niri's defaults bind it to `switch-preset-column-width-back`.
`Mod+Alt+R` is free. Absolute path per the [[feedback-niri-spawn-path]]
gotcha.

**Verification:**

`Mod+Alt+R` → slurp lets you drag a region → bar shows the pulsing red
`󰻂`. `Mod+Alt+R` again (or click the pill) → wf-recorder flushes,
notification points at the saved MP4 under `~/Videos`.

---

## Step 34 — Voxtype push-to-talk dictation (Omarchy port)

**Goal:** local Whisper-powered voice-to-text at the cursor, on a single
key. Mirrors Omarchy's bin/omarchy-voxtype-* tooling.

**Install (run interactively):**

```sh
paru -S voxtype-bin
voxtype setup --download --model base --no-post-install   # ~150 MB
voxtype setup systemd
systemctl --user enable --now voxtype
```

`voxtype-bin` is the upstream peteonrails/voxtype AUR package; ships
its own systemd user unit + `voxtype` CLI. The Whisper `base` model
(multilingual) lives at `~/.local/share/voxtype/models/ggml-base.bin`.

**Config** at `~/.config/voxtype/config.toml` — port of
`basecamp/omarchy@master:default/voxtype/config.toml` with two changes:

- `[whisper] model = "base"` and `language = "auto"` (Omarchy ships
  `base.en` — English-only — but this is a DE/EN system, so we pay a
  small accuracy/perf cost for multilingual detection).
- `[hotkey] enabled = false` (kept from upstream): voxtype's own
  hotkey grabber is disabled because niri drives the keybinds.

State file at `$XDG_RUNTIME_DIR/voxtype/state` holds one of
`idle / recording / transcribing`. Voxtype overwrites it on every
state transition. The bar widget inotify-watches that path so the
icon flips instantly.

**Bar widget:** `~/.config/quickshell/Voxtype.qml`. Pattern matches
ScreenRecord (FileView + state-driven icon, pulse animation while
recording). Glyphs from Omarchy waybar's `custom/voxtype.format-icons`:

- idle:         `󰍮` (nf-md-microphone_off) in `Theme.fgDim`
- recording:    `󰍬` (nf-md-microphone)     in `Theme.urgent`, pulsing
- transcribing: `󰔟` (nf-md-timer_sand)     in `Theme.accent`

Hidden entirely when the daemon isn't running (state file absent).
Click toggles dictation (same as `Mod+Ctrl+X`). Slotted into the
centre cluster after `Updates`, matching Omarchy waybar's
modules-center order (clock → weather → update → voxtype → …).

**Niri keybinds:**

```kdl
F9 allow-when-locked=false hotkey-overlay-title="Toggle dictation (F9)" {
    spawn "voxtype" "record" "toggle";
}
Mod+Ctrl+X hotkey-overlay-title="Toggle dictation" {
    spawn "voxtype" "record" "toggle";
}
```

**Limitation (niri 26.04):** ideal Omarchy parity is hold-F9 push-to-talk
via Hyprland's `bindd` + `binddr`. Niri's equivalent
`event="down"` / `event="up"` keybind property is in
[niri-wm/niri#2456](https://github.com/niri-wm/niri/pull/2456), still
open at the time of writing. Until that lands, F9 is a press-once-to-
start, press-again-to-stop toggle. When the PR ships, swap to:

```kdl
F9 event="down" { spawn "voxtype" "record" "start"; }
F9 event="up"   { spawn "voxtype" "record" "stop"; }
```

**Verification:**

```sh
systemctl --user status voxtype | head -3
cat /run/user/$(id -u)/voxtype/state    # "idle"
```

Press F9 in a text field, speak, press F9 again — transcript types at
the cursor. Bar icon flips idle → recording (red pulse) → transcribing
(sand timer) → idle.

---

## Step 35 — Calendar polish (week numbers, multi-month nav)

**Goal:** address the Phase C "Calendar popup — improvements" item.

**Changes to `~/.config/quickshell/Calendar.qml`:**

- **Week-number column.** ISO 8601 week numbers (`Wk` header + a faint
  number per row) on the left of the 7-day grid. `isoWeek(Date)`
  helper computes per the standard "Thursday in this week determines
  the year" rule.
- **Monday-first week.** Mon..Sun column order, matching ISO and German
  convention. Omarchy starts on Sunday — deviation called out in the
  file. `firstDayOffset = (startOfMonth.getDay() + 6) % 7`.
- **Multi-month nav.** Header is now `«  ‹  Month YYYY  ›  »` with year
  jumps (`«` / `»` = nf-md-chevron_double_left/right) flanking the
  existing month jumps (`‹` / `›`). Inline `component NavButton` keeps
  the four buttons from drowning the file.
- **Click-to-today.** Clicking the `MMMM yyyy` label resets `viewMonth`
  to the current date — useful after deep year-jump navigation.
- **Weekend tinting.** Sat / Sun day columns render in `Theme.fgDim` so
  the work week is visually separable.

**File width** bumped from 320 to 360 px to fit the extra column without
crowding day cells.

**Verification:**

Click the clock in the bar → popup opens. Header shows
`«  ‹  Mai 2026  ›  »` (Qt picks the locale's month name). Left column
shows week numbers (`19` for the row containing 2026-05-04, etc.).
Year chevrons jump by 12 months at a time. Clicking the month name
returns to today.

---

## Step 35b — Locale-aware Calendar + Weather

**Symptoms after Step 35:** the Calendar header still said `May 2026` and
the day row was `M T W T F S S` despite the system locale being
`de_DE.UTF-8`. Weather popup showed `FEELS WIND HUMID`. After we wired
locale handling, "FÜHLT" was grammatically off — German weather UIs use
the past participle `gefühlt`.

**Root causes:**
- niri 26.04 itself is started without `LANG` in env on this Arch
  install, so every spawn-at-startup child (quickshell included)
  inherited the C locale. The .qslog confirmed `Qt.locale()` returned
  `C` rather than `de_DE` for the auto-started shell.
- `Qt.formatDate()` defaults to the QML engine's locale which, in
  pragma-`UseQApplication` mode, is sometimes still `C` even after the
  application is initialized — `Qt.locale().toString(value, fmt)` is
  always locale-aware so we use that path instead.
- Hardcoded English `FEELS / WIND / HUMID` labels in the Weather popup,
  with no locale dispatch.

**Fixes:**

- `~/.config/niri/config.kdl` top of file:

  ```kdl
  environment {
      LANG "de_DE.UTF-8"
      LC_TIME "de_DE.UTF-8"
  }
  ```

  niri exports these into every spawned child, including auto-started
  quickshell at session start.

- `~/.config/quickshell/Calendar.qml`:
  - `Qt.formatDate(...)` → `Qt.locale().toString(..., fmt)` for both
    the bar pill (`dddd HH:mm`) and the popup's `MMMM yyyy` header.
  - Day-of-week headers from `Qt.locale().standaloneDayName(qtDay,
    Locale.ShortFormat)`, trimmed + sliced to 2 chars.
    German → `Mo Di Mi Do Fr Sa So`. English → `Mo Tu We …`.
  - `firstDayOfWeek` from `Qt.locale().firstDayOfWeek` so US locales
    start on Sunday; the row math (`firstDayOffset = (startOfMonth.
    getDay() - firstDayOfWeek + 7) % 7`) follows.
  - ISO week number computed from each row's **Thursday** (not its
    first cell), so the week column stays correct in Sunday-first
    locales where the row spans two ISO weeks.
  - Small lookup table for the week-column header: `KW` for German,
    `Sem` for French/Spanish/Portuguese, `Set` for Italian, `Wk`
    otherwise.

- `~/.config/quickshell/Weather.qml`:
  - `dayName()` switched to `Qt.locale().toString(d, "ddd")`.
  - Stat labels (`FEELS / WIND / HUMID`) routed through a small
    `tr(key)` lookup keyed on the 2-letter locale prefix. German
    settled on `GEFÜHLT / WIND / FEUCHTE` after rejecting the
    grammatically wrong `FÜHLT` and the noun-mismatched `FEUCHT`.

**Verification:**

```sh
cat /proc/$(pgrep -x niri)/environ | tr '\0' '\n' | grep LANG
# (after a niri reload — LANG=de_DE.UTF-8)
cat /proc/$(pgrep -x quickshell)/environ | tr '\0' '\n' | grep LANG
# same
```

Open the calendar: header reads `Mai 2026`, day row `KW Mo Di Mi Do Fr
Sa So`. Open the weather popup: `GEFÜHLT WIND FEUCHTE` labels with
locale-formatted forecast `Mo Di Mi …` day names.

---

## Step 36 — External-monitor brightness via ddcutil

**Goal:** wire `XF86MonBrightness{Up,Down}` to ramp all DDC/CI-capable
external monitors together, reusing the Step-27 OSD bezel for feedback.

**Why this is its own item (not Omarchy parity):** Omarchy's
`bin/omarchy-brightness-display` uses `brightnessctl` against
`/sys/class/backlight/*`, which is the laptop-backlight path. This 3 ×
DP desktop has no `/sys/class/backlight` entries at all — `brightnessctl`
finds nothing and no-ops. ddcutil over the I²C DDC/CI bus is the right
tool for external panels.

**One-time host setup** (interactive, needs sudo + a reboot for the new
kernel modules to mount):

```sh
sudo pacman -S --needed ddcutil
sudo usermod -aG i2c $USER
echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf
# Reboot — `sudo modprobe i2c-dev` will fail right after a kernel
# upgrade because the new modules tree isn't loaded yet.
```

After reboot, `groups | grep i2c` confirms membership, `lsmod | grep
i2c_dev` confirms the module, and `ls /dev/i2c-*` lists buses. Then
`ddcutil detect` enumerates each monitor with its bus number and EDID.

**Helper script:** `~/.local/bin/qs-brightness-display`. Patterns the
qs-audio-output-volume / qs-osd workflow:

- Discover I²C bus numbers via `ddcutil detect --terse`.
- Resolve the new brightness value (`raise` / `lower` = ±5, `±N`
  delta, or absolute `N`).
- Fan out `ddcutil --bus=N --brief setvcp 10 <value>` to every
  detected monitor in parallel — DDC/CI commits take ~0.5–2 s per
  panel, so serial would be painful on the three displays.
- Read the new percent off the first monitor and pass it to
  `qs-osd -i brightness -p <pct>` so the bezel shows.
- `PATH="$HOME/.local/bin:$PATH"` at the top so the nested `qs-osd`
  lookup works under niri's bare PATH — same [[feedback-niri-spawn-path]]
  issue as the volume scripts.

**Niri keybinds** in `~/.config/niri/config.kdl`:

```kdl
XF86MonBrightnessUp   allow-when-locked=true { spawn "/home/michael/.local/bin/qs-brightness-display" "raise"; }
XF86MonBrightnessDown allow-when-locked=true { spawn "/home/michael/.local/bin/qs-brightness-display" "lower"; }
```

(Replaces the niri-default `brightnessctl --class=backlight` lines that
were no-ops on this hardware.)

**Verification:**

```sh
ddcutil detect | grep ^Display
qs-brightness-display raise && qs-brightness-display lower
# bezel pops twice; physical screens visibly brighten/dim
```

---

## Step 37 — Per-output named workspaces (reverted)

**Outcome:** reverted. The named workspaces (`main` / `side` / `top`)
introduced extra always-present pills on every bar that didn't map to
anything meaningful for this user's workflow, and the placeholder
labels obscured the simple `1 2 3` idx layout people are used to.
`config.kdl` keeps a short comment in place of the workspace blocks
pointing back to this section.

**For future reference**, the steps below describe what *was* tried;
add back any subset if you ever want labelled persistent workspaces.

**Goal:** label workspace 1 on each output with a name instead of just
the index, so the bar pill reads "main" / "side" / "top" rather than
three identical "1"s across the three monitors.

**niri-native, not a bar-side override.** niri 26.04 supports
declaring persistent named workspaces in config and exposes the name
on the workspace JSON object (`niri msg --json workspaces` →
`{"idx":1, "name":"main", "output":"DP-1", …}`). The Quickshell
`Workspaces.qml` already renders `modelData.name || idx`, so no QML
change was needed — the work is entirely in niri config.

**Config addition** to `~/.config/niri/config.kdl` (after the `output`
blocks, before `layout`):

```kdl
workspace "main" {
    open-on-output "DP-1"
}
workspace "side" {
    open-on-output "DP-2"
}
workspace "top" {
    open-on-output "DP-3"
}
```

Each `workspace "<name>"` block creates a **persistent** workspace
pinned to the given output — the workspace appears in the bar even
when empty.

**Interaction with existing binds:**

- `Mod+1..9` continues to focus by **idx within the focused output**,
  so default muscle memory keeps working.
- To focus by name from any output, add e.g.:
  ```kdl
  Mod+Shift+M { focus-workspace "main"; }
  ```
  Not added by default — too easy to overload Mod+Shift+<letter>
  bindings that already mean other things.

**Verification:**

```sh
niri msg --json workspaces \
  | python3 -c 'import sys,json;[print(w["output"], w["idx"], repr(w["name"])) for w in sorted(json.load(sys.stdin), key=lambda w:(w["output"], w["idx"]))]'
```

Should report:

```
DP-1 1 'main'
DP-1 2 None
…
DP-2 1 'side'
…
DP-3 1 'top'
…
```

In the bar, each monitor's first pill now shows its name; subsequent
pills (idx 2, 3, …) stay numeric.

---

## Step 38 — Post-Phase-C UX refinements

Small fixes that didn't fit cleanly into their original step blocks:

**`Tray.qml` — left-click prefers the menu when hasMenu is true.**
Ayatana indicators (Remmina, lots of Electron apps) advertise
`hasMenu: true` but stub `activate()`, so left-click on Step 31b's
tray cells did nothing on those apps. Now: if `hasMenu`, left-click
opens the same `QsMenuAnchor` that right-click does; otherwise
`activate()` runs. Apps that really want left-click activation (Discord,
Steam) typically also expose an "Open …" menu entry, so this is a net
improvement in cross-app behaviour.

**`Weather.qml` — gate the fetch on location resolution + fast retry.**
On reboot, Step 31's Weather widget showed wrong data: the first curl
fired before geojs.io had returned, so it used the default Berlin
fallback coords (~250 km off from Oberlungwitz) and the user had to
click-refresh manually. Two fixes:

- `refresh()` now early-returns if `locationKnown` is false (and kicks
  off the locationProc if not already running). `locationProc.onExited`
  re-calls refresh() once location is set — or, if location lookup
  failed entirely, after the first try it marks `locationKnown=true`
  with the Berlin fallback so the user still gets *something*.
- The auto-refresh timer interval is now `current ? 15min : 30s`. While
  no data has landed it retries every 30 s; once a fetch succeeds it
  backs off to the normal 15-minute cadence. Handles the "logged in
  before the network came up" case without burning a tight loop forever.

**`Voxtype.qml` — hide when idle.** Step 34 left a permanently-visible
microphone glyph in the bar when voxtype was running but not actively
dictating. The `any` flag is now `recording || transcribing` (no longer
includes `idle`), so the widget is only visible while something
is actually happening. Daemon-not-running still hides the widget too
(no state file).

**`Media.qml` — strip the scrolling title.** The MPRIS now-playing
widget's right-half was an infinite NumberAnimation scrolling
`title  ·  artist` through a 180-px clip rect. Distracting in a top
bar. The widget is now just the play/pause glyph; right-click still
opens the popup with art + full title + artist + transport pills.

**`Notifications.qml` — hide when no notifications pending.** The bell
glyph was visible at all times in Step 24. The widget's `implicitWidth`
is now `active ? pill.width : 0` and `visible: active`, so it appears
only when there's at least one un-dismissed notification.

---

## Phase C complete

Every item from the original Phase C polish list is now landed:

- ✅ Step 27 — OSD bezel for volume / mute (Omarchy port)
- ✅ Step 28 — Clipboard history picker (cliphist + Omarchy port)
- ✅ Step 29 — Power menu (Lock / Suspend / Logout / Restart / Shutdown)
- ✅ Step 30 — Pacman update-count widget
- ✅ Step 30b — Updates singleton + pacman-log inotify + center placement
- ✅ Step 31 — Weather widget + flyout
- ✅ Step 31b — Tray widget fixes (clicks + platform menus)
- ✅ Step 32 — Emoji picker (Omarchy port)
- ✅ Step 33 — Screen recording (wf-recorder) + indicator
- ✅ Step 34 — Voxtype push-to-talk dictation (Omarchy port)
- ✅ Step 35 — Calendar polish (week numbers, multi-month nav)
- ✅ Step 35b — Locale-aware Calendar + Weather (GEFÜHLT / KW / Mai …)
- ✅ Step 36 — External-monitor brightness via ddcutil
- ⏭  Step 37 — Per-output named workspaces (tried, reverted)
- [ ] Quickshell Calendar popup — improvements (week numbers, multi-month nav)
- [ ] Per-output workspace name overrides
