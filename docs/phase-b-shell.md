## Step 8 — Install Quickshell, scaffold the bar

**Goal:** stand up a niri-aware top bar.

```sh
sudo pacman -S --needed quickshell
mkdir -p ~/.config/quickshell
```

Create these files under `~/.config/quickshell/` (full contents live in
each file — the script should `cat > path <<EOF … EOF` or copy from
template):

- `shell.qml` — entry point. `ShellRoot { Variants over Quickshell.screens → Bar; Variants → NotificationToast; Launcher {} }`
- `qmldir` — module manifest (singletons + components).
- `Theme.qml` — color palette + sizes singleton. Omarchy-style: bg `#101315`, fg `#cacccc`, urgent `#a55555`, JetBrainsMonoNL Nerd Font.
- `Bar.qml` — PanelWindow per screen, top-anchored, 32 px, left/center/right sections.

Launch with `quickshell` (interactively in kitty for log visibility).

---

## Step 9 — NiriService singleton + Workspaces widget

**Goal:** single subscription to `niri msg --json event-stream` exposed
as a singleton; workspace pills on the bar driven from it.

Files:
- `~/.config/quickshell/NiriService.qml` — owns one `Process` running
  `niri msg --json event-stream`, parses WorkspacesChanged, WorkspaceActivated,
  WindowsChanged, WindowFocusChanged, KeyboardLayouts*. Exposes
  `workspaces`, `windows`, `focusedWindow*`, plus helpers `runAction(...)`,
  `focusWorkspace(idx)`, `launchTui(name, ...args)`.
- `~/.config/quickshell/Workspaces.qml` — pill row sorted by `idx`, filtered
  to current output. Click sends `niri msg action focus-workspace <idx>`.

Both registered in `qmldir`.

**Verification:** workspaces appear sorted on each monitor; click switches.

---

## Step 10 — ActiveWindow widget (compositor-agnostic)

**Goal:** focused-window title in the bar (left section).

- `~/.config/quickshell/ActiveWindow.qml` — uses
  `Quickshell.Wayland.ToplevelManager.activeToplevel` (wlr-foreign-toplevel
  protocol — works on niri identically to Hyprland). Title widthed via
  `TextMetrics` (avoids QML binding loop). Animated width 180 ms. Left
  click → `NiriService.runAction("maximize-column")`. Middle / right
  click → `toplevel.close()`.

**Verification:** focusing any app shows its title in the bar; clicking
maximizes the column; middle-click closes.

---

## Step 11 — Audio widget (Pipewire)

**Goal:** volume / mute indicator with TUI mixer escape hatch.

- `~/.config/quickshell/Audio.qml` — uses `Quickshell.Services.Pipewire`,
  default sink's `audio.volume` / `audio.muted`. Left click toggles mute,
  scroll ±5 %, right click → `NiriService.launchTui("wiremix")`.

Requires `wiremix` package (installed in Step 17).

---

## Step 12 — System Tray widget

**Goal:** show StatusNotifierItem icons (Discord/Slack/Steam/etc.).

- `~/.config/quickshell/Tray.qml` — `Quickshell.Services.SystemTray.items`
  in a Row. Left = activate, middle = secondary, right = context menu.

No system change needed; SNI works out of the box once an app registers.

---

## Step 13 — Calendar widget with month-grid popup

**Goal:** clock + click → month-grid popup. Faithful port of Omarchy's
`calendar.qml` minus Omarchy-only deps.

- `~/.config/quickshell/Calendar.qml` — `SystemClock { precision: Minutes }`,
  ISO-week helper. `PopupWindow` with `anchor.window: barWindow`,
  `anchor.rect.x/y` for below-bar centering. Month grid: 7 columns × 6 rows,
  week starts Sunday, today filled with `Theme.fg`. Prev/next chevrons.

Bar.qml passes `barWindow: bar` to Calendar.

**Key API discovery (recorded):** Quickshell `PopupWindow` uses
`anchor.window: <PanelWindow>` and `anchor.rect.x/y` for position — NOT
`QsWindow.window`. My first attempt with `QsWindow.window` crashed.

---

## Step 14 — SystemStats + btop floating launcher

**Goal:** chip icon → hover popup with CPU / Memory / Load sparklines;
click launches `btop` in a floating kitty.

```sh
sudo pacman -S --needed btop
```

- `~/.config/quickshell/SystemStats.qml` — three `Process` readers
  (`head -n1 /proc/stat`, `head -n3 /proc/meminfo`, `cat /proc/loadavg`),
  refresh every 2 s, 30-sample sparkline history, hover popup with 220 ms
  grace. Click → `NiriService.launchTui("btop")`.

**niri window rule for TUIs** in `~/.config/niri/config.kdl`:

```kdl
window-rule {
    match app-id=r#"^tui-"#
    open-floating true
    default-column-width { fixed 1000; }
    default-window-height { fixed 640; }
}
```

`NiriService.launchTui(name)` spawns
`kitty --class=tui-<name> --override initial_window_width=120c --override initial_window_height=32c -e <name>`.

---

## Step 15 — Media widget (MPRIS)

**Goal:** play/pause + scrolling "title · artist" in the bar (right
section), right-click popup with album art + transport pills.

- `~/.config/quickshell/Media.qml` — `Quickshell.Services.Mpris.Mpris.players`.
  Activates: left = togglePlaying, middle = next, right = popup, wheel
  ±= prev/next. Inline `TransportPill` sub-component for buttons.

Hidden when no MPRIS player has a track.

---

## Step 16 — Switch to JetBrainsMono Nerd Font

**Goal:** Omarchy's bar font + icon glyphs.

```sh
sudo pacman -S --needed ttf-jetbrains-mono-nerd
```

In `~/.config/quickshell/Theme.qml`, set `monoFamily`, `sansFamily`,
`iconFamily` all to `"JetBrainsMonoNL Nerd Font"` (the no-ligature
variant). Add `iconPx: 15` for icon-specific sizing.

Replace Audio/SystemStats/etc. emoji glyphs with Material Design Icon
codepoints (`󰕾`, `󰍛`, `󰏤`, etc.) bundled in the Nerd Font.

---

## Step 17 — Phase B Tier 1 packages

**Goal:** install everything the rest of the shell needs in one go.

```sh
sudo pacman -S --needed \
    pacman-contrib wl-clipboard grim slurp satty \
    fuzzel swaylock swayidle swaybg \
    bluez bluez-utils bluetui wiremix \
    libnotify
```

Then enable the bluez service:

```sh
sudo systemctl enable --now bluetooth
```

All packages are in `extra`. `libnotify` is just for `notify-send`
manual testing — the actual notification daemon is the Quickshell service
we add in Step 24.

---

## Step 18 — Bluetooth widget

**Goal:** bar icon for adapter state, click → `bluetui` TUI.

- `~/.config/quickshell/Bluetooth.qml` — polls
  `bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2 }'` every 5 s.
  Icon `󰂯` (on) / `󰂲` (off). Click → `NiriService.launchTui("bluetui")`.

Placed between Tray and Network in `Bar.qml` right section.

---

## Step 19 — Wallpaper via swaybg

**Goal:** solid dark wallpaper matching the bar bg. Auto-start at niri start.

Append to `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "swaybg" "-c" "#101315"
```

For an image instead:

```kdl
spawn-at-startup "swaybg" "-i" "/home/michael/Bilder/wallpaper.jpg" "-m" "fill"
```

To start now without restarting niri: `swaybg -c "#101315" &` in any terminal.

---

## Step 20 — Idle lock: swaylock theme + swayidle

**Goal:** auto-lock after 5 min idle, displays off after 10 min, lock
before suspend. Lock screen themed to match bar palette.

`~/.config/swaylock/config` — Omarchy-ish dark theme with bg `#101315`,
indicator using `Theme.bgAlt` / `Theme.fg` / `Theme.urgent` colors,
JetBrainsMonoNL Nerd Font.

Append to `~/.config/niri/config.kdl`:

```kdl
spawn-sh-at-startup "swayidle -w timeout 300 'swaylock -f' timeout 600 'niri msg action power-off-monitors' before-sleep 'swaylock -f'"
```

`Super+Alt+L` was already bound to `swaylock` in the default config.

To start swayidle now: run the same command in a terminal with `&`.

---

## Step 21 — Screenshot keybind: grim + slurp + satty

**Goal:** select region → annotate → save to XDG_PICTURES_DIR/Screenshots
AND copy to clipboard. Keybind via `Mod+Shift+S` (no Print key on this
keyboard). Drop the default Print/Ctrl+Print/Alt+Print bindings.

In `~/.config/niri/config.kdl`:

```kdl
// Match satty (the annotation window) into the floating TUI rule:
window-rule {
    match app-id=r#"^tui-"#
    match app-id="com.gabm.satty"
    open-floating true
    default-column-width { fixed 1000; }
    default-window-height { fixed 640; }
}

// In binds {}: remove Print/Ctrl+Print/Alt+Print bindings, add:
Mod+Shift+S allow-when-locked=false hotkey-overlay-title="Screenshot region (satty)" {
    spawn-sh "DIR=\"$(xdg-user-dir PICTURES)/Screenshots\"; mkdir -p \"$DIR\"; grim -g \"$(slurp -o -d)\" - | satty --filename - --output-filename \"$DIR/Screenshot_$(date '+%Y-%m-%d_%H-%M-%S').png\" --early-exit --copy-command wl-copy"
}
```

Update niri's `screenshot-path` to `~/Bilder/...` (German locale; niri
does no env-var expansion there).

**Verification:** press `Mod+Shift+S` → slurp lets you drag a region →
satty opens floating 1000×640 for annotation → save writes to
`~/Bilder/Screenshots/Screenshot_YYYY-MM-DD_HH-MM-SS.png` + clipboard.

---

## Step 22 — Network widget (read-only, systemd-networkd)

**Goal:** Ethernet status icon + click → popup with IP/gateway/speed.

System is **systemd-networkd** (no Wi-Fi adapter, no NetworkManager). We
briefly tried NM + nmtui — nmtui is unreasonably ugly. Rolled back. iwd
would be the Omarchy parity but doesn't apply without Wi-Fi hardware.

```sh
# Confirm rollback if NetworkManager ever got installed by mistake:
sudo systemctl disable --now NetworkManager 2>/dev/null
sudo systemctl enable --now systemd-networkd
sudo pacman -Rs networkmanager 2>/dev/null || true
```

- `~/.config/quickshell/Network.qml` — polls
  `ip route get 1.1.1.1` + `/sys/class/net/<iface>/{speed,duplex}` every 3 s.
  Icon `󰈀` connected / `󰈂` disconnected. Click → popup card with IP,
  gateway, link speed.

Placed between Bluetooth and SystemStats in `Bar.qml`.

---

## Step 23 — Quickshell launcher (replaces fuzzel)

**Goal:** keep the launcher inside the shell — same Theme tokens,
walker-style look.

- `~/.config/quickshell/Launcher.qml` — single PanelWindow filling the
  screen with a dimmed background + centered 620×540 card. `TextInput`
  with magnifier glyph (`󰍉`), `ListView` filtered from
  `DesktopEntries.applications.values` (the `DesktopEntries` type lives
  in core `Quickshell`, **not** a separate import). Icons via
  `Quickshell.iconPath(name, true)`. Keyboard nav: Up/Down/Tab cycle,
  Enter launches, Esc closes. Hover also moves selection.
  WlrLayershell with Exclusive keyboard focus.

In `shell.qml`: add `Launcher {}` as a single-instance child (NOT per
screen via Variants).

In niri config, replace the Mod+D bind:

```kdl
Mod+D hotkey-overlay-title="App launcher" {
    spawn "quickshell" "ipc" "call" "launcher" "toggle";
}
```

---

## Step 24 — Notifications: in-shell daemon + bar widget + toast surface

**Goal:** drop-in `org.freedesktop.Notifications` daemon, no external
mako/dunst. Bar bell + toasts at top-right.

Files in `~/.config/quickshell/`:
- `NotificationService.qml` — singleton wrapping
  `Quickshell.Services.Notifications.NotificationServer`. On `notification`
  signal: set `n.tracked = true`, snapshot to JS object, deduplicate by
  `originalId`, prepend to `popups`. `dismiss(idx)` calls `ref.dismiss()`.
- `NotificationToast.qml` — PanelWindow per screen, layer Overlay, no
  keyboard focus, ExclusionMode.Ignore. Stack of 380 px cards top-right.
  Each card has its own lifetime timer (3 s low / 5 s normal / sticky
  critical) with a progress bar; hover pauses; click dismisses.
- `Notifications.qml` — bar widget with bell `󰂜` (active) / `󰂚` (idle) +
  count. Left = dismiss top, right = dismiss all.

In `shell.qml`: add a Variants block over `Quickshell.screens` for
NotificationToast. In `Bar.qml`: add Notifications between Tray and
Bluetooth.

**Verification:**
```sh
notify-send "Hello" "Body"
notify-send -u critical "Sticky" "Stays until clicked"
notify-send -u low "Low" "3-second lifetime"
```

Bell icon lights up; toasts cascade from top-right; progress bars
animate; hover pauses; click dismisses.

---

## Step 25 — Auto-start the shell from niri

**Goal:** stop spawning `waybar` (not installed), start `quickshell` at
login instead.

In `~/.config/niri/config.kdl`, replace the existing
`spawn-at-startup "waybar"` line with:

```kdl
spawn-at-startup "quickshell"
```

(Steps 19 and 20 also added swaybg and swayidle spawn lines around here.)

**Verification:** `niri validate` is clean; logging out + back in starts
quickshell, swaybg, and swayidle without any manual launches.

---
