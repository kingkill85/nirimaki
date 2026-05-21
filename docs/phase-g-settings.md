# Phase G — Settings dialogs (Quickshell) ✅

A unified settings menu in Quickshell, modelled on Omarchy's
`omarchy-menu` system (Super+Alt+Space). Hierarchical category →
action selector, all rendered through our existing Quickshell
overlay style.

## Research — what Omarchy ships

Source: `basecamp/omarchy:bin/omarchy-menu`. Walker-driven menu,
hierarchical, key-launched.

Top-level (8 categories):

| Icon | Category | Subentries |
|------|----------|------------|
| 󰀻 | **Apps** | walker app launcher (full mode) |
| 󰧑 | Learn | docs |
| 󱓞 | **Trigger** | Reminder · Capture · Transcode · Share · Toggle · Hardware |
| 󰸌 | **Style** | Theme · Unlock · Font · Background · Waybar · Corners · Hyprland · Screensaver · About |
| 󰒓 | **Setup** | Audio · Wifi · Bluetooth · Power Profile · System Sleep · Monitors · Keybindings · Input · Defaults · DNS · Security · Config |
| 󰉉 | Install | per-app installer |
| 󰭌 | Remove | per-app uninstaller |
| 󰚰 | Update | full / Waybar / Hyprland / Walker |
| 󰐥 | **System** | Screensaver · Lock · Suspend · Hibernate · Logout · Restart · Shutdown |

Each leaf either:
- launches a GUI tool (`omarchy-launch-audio` → pavucontrol-style)
- opens a config file in the editor
- runs a one-shot system action (`systemctl suspend`)
- opens a deeper submenu (Walker `--dmenu` shell)

## Scope for OUR Quickshell — only what we currently support

Drop categories where we ship nothing (Install / Remove / Update —
no `omarchy-pkg-*` here; Learn — no docs site; Trigger.Reminder /
Hardware / Transcode — feature gap). Wire each entry to either an
existing Quickshell overlay (via IPC), an installed GUI tool, or a
direct compositor/system action.

Final category map:

| Category | Entries | Backing action |
|----------|---------|----------------|
| **Style** | Theme · Background · Keybinds | IPC: theme-picker / background-picker / keybind-sheet |
| **Setup** | Audio · Bluetooth · Network · Display · Language | exec: pavucontrol / blueman-manager / (niri msg outputs popup) · IPC: language-picker (new, G3) |
| **System** | Lock · Suspend · Logout · Restart · Shutdown | (mirrors PowerMenu — wire to the same actions) |

`Apps` not duplicated — `Mod+Space` already opens the Launcher.
`Trigger.Capture` (screenshot) and `Trigger.Toggle` (notifications)
left out for now; can fold in later.

## Step targets

| Step | Topic | What changes |
|------|-------|--------------|
| **G1** | Audit installed GUI tools | `pavucontrol`/`pwvucontrol`, `blueman-manager`, etc. — what's actually present, what to install. |
| **G2** | `SettingsMenu.qml` shell | New overlay, scrim + bordered card, breadcrumb header, drilldown navigation, filter input. Same look as ThemePicker / KeybindSheet. |
| **G3** | Style submenu | Theme / Background / Keybinds entries — each forwards to existing IPC overlay. |
| **G4** | Setup submenu | Audio / Bluetooth / Network / Display / Language. Each entry either `execDetached` a GUI tool or opens a Quickshell info popup. |
| **G5** | System submenu | Lock / Suspend / Logout / Restart / Shutdown — wire to the same commands PowerMenu already uses, OR proxy through PowerMenu's IPC. |
| **G6** | i18n + keybind | All labels into `i18n/{en,de}.json`. Bind `Mod+Alt+Space` → `quickshell ipc call -- settings-menu toggle`. |
| **G7** | Decide PowerMenu's future | Keep PowerMenu as fast-access shortcut (`Mod+Escape`) — common ops shouldn't need two clicks. Or drop, redirect Mod+Escape to settings-menu's System submenu. |

## Locked decisions

1. **Drilldown UX (replace-in-place).** Single overlay swaps its
   contents as the user drills in; breadcrumb in the header
   (`Settings › Setup`). Esc pops one level; root Esc dismisses.
2. **External TUIs for hardware — Omarchy-style.** Audio /
   Bluetooth / WiFi launch the same kitty-floating TUIs Omarchy
   uses:
   - **Audio** → `wiremix` (already installed)
   - **Bluetooth** → `bluetui` (already installed); the launcher
     also `rfkill unblock bluetooth` first, like Omarchy
   - **WiFi** → `impala` (in `extra`, install on demand). Our
     user is on Ethernet so this entry is low priority — included
     for completeness.
   Launched via `kitty --class=tui-<name>` so niri's existing
   floating-TUI window-rule catches them (1000×640 centred).
3. **Language picker** — fresh overlay listing `i18n/*.json` files
   minus the `en` fallback. Selecting one writes
   `~/.config/quickshell/locale` (one line: 2-letter code). The
   `I18n` singleton reads that file first, falls back to
   `LC_MESSAGES` / `LANG`. Needs a small I18n change in G4.

## Risks

- Settings submenus that just `execDetached` GUI tools (pavucontrol)
  break the visual consistency we just locked down in Phase E.
  Mitigation: cluster all "external tool" entries under Setup, mark
  them with a small "↗" glyph so the user knows they leave the
  shell-styled flow.
- The drilldown navigation adds state (current path) that the
  existing pickers don't have. Keep the state machine simple: a
  stack of paths; back pops one; root dismisses.
- We don't ship `pavucontrol` / `blueman-manager` yet. Audio and
  Bluetooth entries will need a package install in G4 — flag the
  missing tool gracefully ("not installed — install?") rather than
  silently failing.

## Recommended order

G1 → G2 → G3 → G6 (keybind + i18n) → G4 → G5 → G7

i.e. land the shell + the no-external-deps category (Style)
first, get the keybind wired, then layer Setup + System.

## Sources

- [Omarchy Menu System (DeepWiki)](https://deepwiki.com/basecamp/omarchy/3.1-omarchy-menu-system)
- [omarchy `bin/omarchy-menu`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-menu)

---

## Outcome

- **`~/.config/quickshell/SettingsMenu.qml`** — single overlay with
  a declarative tree (`tree` property: id → `{ icon, labelKey,
  children?, action? }`). Drilldown navigation via a `path` array
  (stack of ids); breadcrumb in the header (`Settings › Setup`).
  Esc / Backspace / Left pops one level (root pop = dismiss);
  Enter / Right activates. Branches render with a `›` glyph.
  Filtering works within the current level. Categories: **Style**
  (Theme / Background / Keybinds — IPC into the existing overlays),
  **Setup** (Audio / Bluetooth / WiFi → TUI spawn, Language →
  picker), **System** (Lock / Suspend / Logout / Restart /
  Shutdown — same commands PowerMenu uses).
- **TUI launches mirror Omarchy:** `kitty --class=tui-wiremix -e
  wiremix`, `kitty --class=tui-bluetui -e bluetui` (with `rfkill
  unblock bluetooth` prefix), `kitty --class=tui-impala -e impala`.
  Niri's existing `app-id=^tui-` window-rule catches them as
  1000×640 floating windows. `wiremix` + `bluetui` were already
  installed; `impala` is `extra/` if you need WiFi.
- **niri keybind**: `Mod+Alt+Space` → `settings-menu toggle`.
  PowerMenu stays on its own bind (`Mod+Escape`) as the fast path
  for power actions.
- **`~/.config/quickshell/LanguagePicker.qml`** — new overlay,
  enumerated from `i18n/*.json` via `FolderListModel`. Synthetic
  first entry "System default" wipes the override file and falls
  back to `LC_MESSAGES` / `LANG`. Selected entry writes
  `~/.config/quickshell/locale` (one line, lowercase 2-letter
  code). `Settings → Setup → Language`.
- **`I18n.qml`** gained `hasOverride: bool` + a FileView on the
  override file as the FIRST resolution step. Order now:
  `~/.config/quickshell/locale` → `LC_MESSAGES` → `LANG` →
  `Qt.locale().name` → `en`. The override file is watched, so the
  picker's write hot-reloads the dictionary.
- **Calendar locale fix.** Was using `Qt.locale()` (Qt's
  application-default, set ONCE from `$LANG` at engine startup
  and unaware of our I18n switch). Replaced every call with a
  bound `readonly property var loc: Qt.locale(I18n.locale)`, so
  month / weekday names re-tint live when the picker fires.

**Resolution chain reference (for future-me):**

```
~/.config/quickshell/locale         (LanguagePicker writes this)
        ↓ missing/empty
$LC_MESSAGES
        ↓ missing/C/POSIX
$LANG
        ↓ missing/C/POSIX
Qt.locale().name
        ↓ all empty
"en"
```

`Settings → Setup → Language → System default` deletes the
override file → resolution falls through to env → highlighted bullet
moves to the "System default" entry.

---

## Appendix — Transparency / blur rework (post-G, same session)

User wanted Omarchy-style blur + per-window-state opacity. Went
through several iterations; final state:

- **Top-level `blur { passes 2; offset 2 }`** in `config.kdl`,
  matching Hyprland's `decoration.blur { size=2; passes=2; }`.
- **Window blur**: `background-effect { blur true; xray false }`
  applied globally. `xray false` is critical — xray mode just
  blurs the wallpaper layer; non-xray reads real pixels so the
  actual apps blur behind translucent windows (matches Omarchy /
  Hyprland behaviour). Caveat per niri wiki: non-xray blur
  briefly disappears during open/close animations and tile
  drags.
- **Per-window-state opacity** (Omarchy `opacity = "0.97 0.9"`
  parity):
    - Default active: `opacity 0.97`
    - Default inactive: `window-rule { match is-active=false
      opacity 0.9 }`
    - Kitty: `opacity 0.85` (no active/inactive split — both
      values would visibly differ on a varied wallpaper, user
      preferred consistency)
    - Floating windows + TUI rule + Firefox PiP: `opacity 0.92`
      (explicit on each rule because `is-floating=true` can race
      with `open-floating true` on launch)
- **Layer-rule blur scoped to Quickshell** namespaces via
  `match namespace=r#"^(quickshell|nirimaki-.*)$"#`, with `xray false`.
  Slurp (`selection`) and swaybg (`wallpaper`) don't match, so
  screenshot region selection + bare wallpaper stay untouched.
- **`draw-border-with-background false` globally** (niri#1823 fix
  hoisted from the kitty-specific rule). Default niri draws the
  focus-ring as a background rectangle BEHIND the window, which
  on any translucent client bleeds the accent colour through the
  interior. Forcing border-as-outline keeps interiors pure on
  ALL translucent windows.
- **kitty.conf gained `background_opacity 0.99`** — niri#2346
  workaround: on AMD, niri's opacity multiplier silently fails
  against opaque RGB buffers. The 0.99 is effectively opaque from
  kitty's side but forces an RGBA buffer that niri can then
  multiply.
- **Inactive border colour** swapped from a fixed `#595959aa` to
  the theme's `{{ color8 }}` (ANSI bright-black, every theme
  defines one). Tried a same-hue/lower-alpha trick first to
  smooth the active↔inactive flicker — user disliked the alpha
  approach, reverted to a contrasting colour. niri 26.04 has no
  focus-color animation (verified against
  `Configuration:-Animations` page — every supported animation
  is window/workspace/overview, none for focus state), so the
  hard-cut flicker is a niri limitation, accepted.

Things niri can't currently match in Omarchy / Hyprland:

| Omarchy / Hyprland | niri 26.04 |
|---|---|
| `blur.brightness 0.6 / contrast 0.75` | n/a — only `passes`, `offset`, `noise`, `saturation` |
| Animated active↔inactive border colour | no `focus-color` animation |
| Reliable opacity on opaque RGB buffers (AMD) | requires the kitty.conf 0.99 trick |
| Non-xray blur during drag / open animation | flickers (experimental flag) |
