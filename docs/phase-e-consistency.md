# Phase E — Visual consistency cleanup

Phases A–D got the shell built. Phase E goes back through the surface
area looking for inconsistencies, then aligns everything to the look
basecamp/omarchy ships:

- Semi-transparent dark cards over a per-theme wallpaper.
- Sharp 90° corners on overlays and window borders.
- 2 px borders, theme accent on focused/active, neutral grey elsewhere.
- Same font (JetBrainsMonoNL Nerd Font) at consistent sizes.
- A theme picker + a background picker as native Quickshell overlays.

Order of work — smallest visible win to biggest refactor:

| # | Topic |
|---|---|
| **E1** | Import all Omarchy themes (and their wallpapers). |
| **E2** | niri borders + CSD matching Omarchy. |
| **E3** | Quickshell visual reset — square corners, transparent cards, font sweep. |
| **E4** | Shared `Surface` component to lock the new look in one place. |
| **E5** | Wallpaper switching — set the active theme's wallpaper via swaybg, swap on `nirimaki-theme-set`. |
| **E6** | Theme picker — Quickshell overlay that lists themes and calls `nirimaki-theme-set`. |
| **E7** | Background picker — Quickshell overlay that lists wallpapers in the current theme. |

---

## Step E1 — Import all Omarchy themes + wallpapers ✅

**Outcome:** 21 themes ported, plus our `default` → 22 total.

**How it landed:**

1. `git clone --depth 1 https://github.com/basecamp/omarchy /tmp/omarchy`.
2. Loop over `themes/*/`, replacing any existing one and `cp -r`'ing
   the rest. Default kept untouched (Omarchy doesn't ship it).
3. User preference re-applied after the import: `tokyo-night/icons.theme`
   set to `Yaru-purple` (Omarchy's choice was `Yaru-magenta`).
4. Cleaned up `/tmp/omarchy`.

**Final theme list** (`nirimaki-theme-list`):
`catppuccin, catppuccin-latte, default, ethereal, everforest,
flexoki-light, gruvbox, hackerman, kanagawa, last-horizon, lumon,
matte-black, miasma, nord, osaka-jade, retro-82, ristretto, rose-pine,
solitude, tokyo-night, vantablack, white`.

Light themes (have `light.mode` marker): `catppuccin-latte`,
`flexoki-light`, `rose-pine`, `white`. The rest are dark.

**Plus one fix to `nirimaki-theme-set` discovered en route:** the script
used `cp -f` per source file which silently skipped subdirectories
(so `backgrounds/` never landed in `current/`). Replaced with:

- Files → still `cp -f` in place (preserves inodes for FileView
  watches).
- Directories → `ln -s <src> <dest>`. Cheap regardless of how big
  `backgrounds/` is (some themes ship 10–16 MB of wallpapers).

**Verification:**

```sh
nirimaki-theme-list                                       # 22 entries
ls ~/.config/theme/themes/gruvbox/backgrounds       # 7 images
nirimaki-theme-set tokyo-night
ls ~/.config/theme/current/                         # symlink to backgrounds/
nirimaki-theme-set default
```

**Open thread:** our `default` theme ships no wallpaper (started life
as a colour-only palette). E5 (swaybg switcher) will need a fallback
for that — solid colour or pick one shared default image.

---

## Step E2 — niri borders matching Omarchy ✅

**Problem:** unfocused windows have no visible border, focused windows
have niri's default focus ring, CSD apps (Zen, GTK4) draw their own
shadow over the top → triple visual style on the same screen.

**Goal:** every window has a 2 px **square-corner** outline. Focused
= theme accent; the rest = muted grey. No CSD doubles.

**Omarchy values** (verbatim from
`basecamp/omarchy@master:default/hypr/looknfeel.conf` +
`default/themed/hyprland.conf.tpl`):

```
border_size           = 2
gaps_in               = 5
gaps_out              = 10
col.active_border     = rgb({{ accent }})       # solid, theme accent
col.inactive_border   = rgba(595959aa)          # fixed grey, ~67% alpha
rounding              = 0                       # sharp corners
```

**Niri translation:**

| Hyprland | Niri |
|---|---|
| `border_size = 2` | `layout.focus-ring.width 2` + `layout.border.width 2` |
| `col.active_border = rgb(<accent>)` | `layout.focus-ring.active.color "<accent>"` |
| `col.inactive_border = rgba(595959aa)` | `layout.border.inactive.color "#595959aa"` |
| `rounding = 0` | nothing — niri doesn't round tile borders by default |
| `gaps_in 5; gaps_out 10` | `layout.gaps 10` (single value in niri) |

**Plan:**

1. Audit current `~/.config/niri/config.kdl` `layout { … }`. Note
   what's set vs default.
2. Update to:
   ```kdl
   layout {
       gaps 10
       focus-ring {
           width 2
           active-color "#cacccc"
           inactive-color "#595959aa"
       }
       border {
           on
           width 2
           active-color "#cacccc"
           inactive-color "#595959aa"
       }
   }
   prefer-no-csd
   ```
3. Re-audit existing `window-rule` blocks (Zen `tiled-state true`,
   kitty `hide_window_decorations`, satty floating). Add per-app
   `window-rule { match app-id="…" prefer-no-csd false }` for any
   that render badly without their own decorations after the toggle.
4. **Theme-tracking** for the active border colour: write
   `~/.config/theme/templates/niri-theme.kdl.tpl` (active-color +
   focus-ring blocks using `{{ accent }}`). `nirimaki-theme-set` renders
   into `~/.config/theme/current/niri-theme.kdl`. Add an
   `include "~/.config/theme/current/niri-theme.kdl"`
   to the main config (or fallback to a `sed` rewrite if niri's
   `include` doesn't apply to `layout` children).

**Risk:** niri refuses to reload on config errors → `niri validate`
before every write. `prefer-no-csd` historically breaks Slack and a
couple of Electron apps → expect 1–2 allow-list rules.

**Verification:**

- kitty + Zen + Nautilus + Qt app open side-by-side, tabbing through
  each: every window has a square 2 px border; focused = theme accent;
  rest = grey. No double-decoration.
- `nirimaki-theme-set tokyo-night` → focus ring instantly Tokyo-Night blue.

### Outcome

- **`~/.config/theme/templates/niri-theme.kdl.tpl`** owns the whole
  `layout { … }` block (gaps 10, default-column-width 0.5,
  preset-column-widths, shadow, struts). `border` has `on` (niri's
  default is off — `width` alone won't enable it), `width 2`,
  `active-color "{{ accent }}"`, `inactive-color "#595959aa"`,
  `urgent-color "#9b0000"`. `focus-ring { off }` — we use **one**
  2 px border that flips colour on focus (cleaner than the
  table-suggested stacked focus-ring + border, which double-draws on
  the active window).
- `nirimaki-theme-set` renders the template into
  `~/.config/theme/current/niri-theme.kdl` like any other `.tpl`,
  and now calls `niri msg action load-config-file` at the end. niri's
  built-in config watcher follows the main file only, not the
  included one, so the explicit reload is required.
- **`~/.config/niri/config.kdl`** had its entire layout block
  replaced with `include "~/.config/theme/current/niri-theme.kdl"`
  near the top. `prefer-no-csd` is now enabled (no app needed an
  allow-list — Zen/Nautilus/kitty/Qt apps all draw cleanly).
- `nirimaki-theme-set <name>` flips the focused-window border in real time;
  switching between gruvbox / tokyo-night / hackerman / nord all
  works.

**Deviation from the original plan:** the plan table mapped
Hyprland's single `border_size = 2` onto **both** `focus-ring.width 2`
and `border.width 2` in niri. That stacks two 2 px outlines on the
focused window (4 px effective). One always-visible `border` with
both `active-color` and `inactive-color` set matches Hyprland's
"one border, colour flips on focus" semantics much better — and is
what's in place now. The `focus-ring` is `off`.

**Initial bug:** my first render had `border { width 2 ... }` without
`on`, which produced *no* borders at all. niri's `border` defaults to
off; you have to explicitly say `on` to enable it (mirror of
`focus-ring { off }`, where the keyword toggles the block). Fix was
one line.

---

## Step E3 — Quickshell visual reset (sharp + transparent + fonts) ✅

**Problem:** Quickshell renders rounded popups (Theme.radius = 8),
fully opaque dark cards, and a mix of fonts (some widgets fall through
to Qt's default DejaVu Sans because they never set `font.family`). The
result is visually distant from Omarchy's launcher screenshot, which
has square corners + a translucent card.

**Goal:** match Omarchy:

- All overlays / popups / pills: **square corners** (radius 0).
- All cards: **translucent dark fill** (~80–90 % opacity over the
  active wallpaper).
- Every `Text { }` uses an explicit `Theme.{mono,sans,icon}Family` and
  a `Theme.fontPx*` token — no Qt defaults, no literal pixel sizes.

**Plan:**

1. Change `Theme.qml`:
   - `radius: 0`
   - Add `cardBg: Qt.rgba(bg.r, bg.g, bg.b, 0.85)` (or expose a
     `cardAlpha: 0.85` token used by card fills).
   - Add `Theme.fontPxSmall` / `Theme.fontPxLarge` if the audit
     turns up recurring sizes.
2. Sweep every QML for:
   - `radius: Theme.radius` — keep (now resolves to 0), or remove the
     property where 0 is clearly the intent.
   - Card / popup `color: Theme.bg` → `color: Theme.cardBg`.
   - Each `Text { }` lacking `font.family` → add the right family.
   - Each literal `font.pixelSize: N` → use a Theme token.
3. The Bar itself should stay opaque (it's a strip, not a card) —
   only popups / overlays go translucent.
4. Plymouth + lock screen are dark-on-dark already, no transparency
   change needed there (and Plymouth can't blur the background
   anyway).

**Risk:** low. Reverting any single edit is one line. The biggest
visible change is "popups look see-through" — fine for the design
goal, occasionally a readability test on light wallpapers; tunable
via `cardAlpha`.

**Verification:**

- Open the Launcher with a wallpaper visible: the card is
  semi-transparent, you can see the wallpaper through it (matches the
  Omarchy screenshot).
- All popup borders are square.
- Every visible string is in JetBrainsMonoNL Nerd Font; no DejaVu
  Sans anywhere.
- `nirimaki-theme-set catppuccin-latte` keeps the alpha and inverts the bg
  tint to light, still readable.

### Outcome

**Theme.qml** got the consistency tokens that everything now reads
from:

- `radius: 0` everywhere (Omarchy sharp corners).
- `cardAlpha: 0.95` + computed `cardBg` (matches Omarchy walker
  `background: alpha(@base, 0.95)`).
- `cardBorderColor: accent`, `cardBorderWidth: 2`. Initially set to
  `fg` (Omarchy literal), then switched to `accent` so popup borders
  match niri's focused-window border colour — compositor↔shell
  consistency was more valuable than a literal port.
- New `menuMargin`/`menuSpacing`/`menuHeaderHeight`/`menuRowHeight`/
  `menuRowSpacing`/`menuFontPx`/`menuIconPx` tokens — every overlay
  (Launcher, PowerMenu, EmojiPicker, ClipboardPicker, future
  pickers) reads from these so they look like one design.
- Font family bumped to `JetBrainsMono Nerd Font` (Omarchy uses the
  proportional-ligature version, not the `NL` no-ligatures variant
  we had before).
- `fontPxLarge` lifted from 16 → 18 to match Omarchy walker's
  `font-size: 18px`. Picker labels/headers use `Theme.menuFontPx`
  which aliases this.

**QML sweep:**

- All five bar popups (Network, Calendar, SystemStats, Weather, Media)
  got the same wrap: PopupWindow becomes transparent, an inner
  Rectangle paints `Theme.cardBg` with `Theme.cardBorderColor`/Width.
  Border is flush with the popup edge (Calendar previously had a
  12 px inset).
- Launcher: dropped the boxed search container + magnifier icon
  (Omarchy walker is just the bare input). Subtitle line removed
  (`.item-subtext { font-size: 0px }`). Selected row uses
  `alpha(fg, 0.07)` background + accent text (matches Omarchy).
- Picker labels switched from `fontPxMedium` (14) to `menuFontPx`
  (18) for parity with Launcher.
- Lock screen `Theme.qml` also went `radius: 0`.

**Popup anchoring (E3.4):**

- Each PopupWindow now anchors to the bar window with an `popupX`
  computed from `pill.mapToItem(barWindow.contentItem, 0, 0).x +
  (pill.width - implicitWidth) / 2`. `popupX` is recomputed in
  `onVisibleChanged` rather than via binding — `mapToItem` is not
  binding-reactive, so a bind-time call returned the pre-layout
  position for pills in anchored Rows (Calendar in `centerIn`,
  SystemStats in the right-anchored Row). Re-evaluating on each show
  reads post-layout coordinates.
- New singleton **PopupBus.qml** (`singleton PopupBus 1.0` in
  qmldir). Each bar widget exposes `popupOpen: bool` and its
  PopupWindow binds `visible: root.popupOpen`. On `onVisibleChanged`
  the widget calls `PopupBus.show(root)` / `.hide(root)`. PopupBus
  sets the previous owner's `popupOpen = false` — clearing the
  source property propagates through the binding; setting
  `visible = false` directly would race against the binding.
- Calendar was converted to the `popupOpen` pattern (was
  toggling `popup.visible` directly) so it integrates with the bus.

**Niri transparency + blur (E3.5, revised post-Omarchy parity check):**

Cross-checked against upstream Omarchy
(`default/hypr/looknfeel.conf` + every file under `default/hypr/apps/`):

| Knob              | Omarchy (hypr)               | Nirimaki (niri)            |
|-------------------|------------------------------|----------------------------|
| Blur size/passes  | `size=2 passes=2`            | `passes 2 offset 2`        |
| Blur tone         | `brightness=0.60 contrast=0.75` | `saturation 1.0` (niri has no brightness/contrast knobs; default 1.5 is too punchy) |
| Default opacity   | `0.97 0.9` (active/inactive) | `opacity 0.97` + `is-active=false opacity 0.9` |
| Terminals         | tagged but **same 0.97/0.9** | inherits default (no override) |
| Floating          | no rule                      | no rule (inherits default) |
| Browsers (Chromium / Firefox families) | `1.0 0.97` (`apps/browser.conf`) | explicit `opacity 1.0` + `is-active=false 0.97` rules matching omarchy's app-id list |
| Media / video / image (zoom, vlc, mpv, kdenlive, OBS, Pinta, imv, NautilusPreviewer) | `1 1` (`apps/system.conf`) | one rule with all 8 app-ids → `opacity 1.0` |
| Picture-in-picture | `1 1`, size 600×338, pin, no border (`apps/pip.conf`) | match by title `(?i)picture.?in.?picture` → `open-floating true`, `opacity 1.0`, fixed 600×338, top-right via `default-floating-position`. No niri equivalent for hyprland's pin. |
| Password managers (1Password, Bitwarden GUI + Chrome extension, KeePassXC, GNOME Secrets) | `no_screen_share on` (`apps/1password.conf` + `apps/bitwarden.conf`) | `block-out-from "screen-capture"` — niri replaces covered pixels with the focus-ring colour in any screencast / screenshot output. |

- Global blur block tunes the dual-kawase parameters so niri's defaults
  (passes 3, offset 3, saturation 1.5) don't read as significantly
  more aggressive than Hyprland.
- Default `window-rule` sets `opacity 0.97`,
  `background-effect { blur true; xray false }`, and
  `draw-border-with-background false`. The last one is the fix for
  niri#1823: without it, niri draws the focus-ring / border as a solid
  background rectangle *behind* the window, which bleeds the accent
  colour through a translucent kitty's interior and makes focused
  kitty look completely different in colour from unfocused. Forcing
  border drawing AROUND the window keeps the interior unaffected.
- `is-active=false` rule drops opacity to 0.9. Together with the
  default 0.97, every window (kitty, floats, PiP, satty, tui-*)
  gets the same active/inactive split as Omarchy.
- Per-app and per-state overrides removed in 2026-05 after user
  flagged that terminals + floats in Nirimaki looked much more
  translucent and visually busier than Omarchy. Removed:
    - `kitty opacity 0.85` (Omarchy keeps kitty at 0.97/0.9)
    - `is-floating=true opacity 0.92` (Omarchy has no floating rule)
    - `opacity 0.92` on PiP and on the tui-*/satty rule (now inherit)
- **No layer-rule blur.** Tried both xray modes for Quickshell
  surfaces:
    - `xray true` (niri's default) — niri replaces the apps behind
      the Launcher with just blurred wallpaper, so apps "disappear"
      from view. Also breaks slurp's region selector.
    - `xray false` — apps stay visible blurred behind, but the
      result reads as visually noisy through the Launcher scrim and
      small popups. User feedback: "the blur sucks there."
  Quickshell popups are 95 % opaque anyway, so no compositor blur
  is fine. Slurp + swaybg are unaffected.

**Wallpaper (groundwork for E5):**

- `~/.local/bin/nirimaki-wallpaper-apply` picks the first image (sorted)
  under `~/.config/theme/current/backgrounds/` and starts swaybg on
  it; falls back to a solid `#101315` if a theme ships no images.
- `niri/config.kdl` spawn-at-startup calls the script; `nirimaki-theme-set`
  calls it after every theme swap.
- Without this, swaybg ran on a solid colour, which made the niri
  blur invisible (blurring a solid colour gives the same solid
  colour) and made the Launcher's 45 % scrim read as plain black.

**Initial bugs hit + fixes:**

- `border { width 2 ... }` without `on` produced no borders at all
  (E2). niri's `border` block defaults to off; the `on` keyword is
  the toggle.
- Calendar got an extra closing `}` on the brace-rebalance when the
  bordered card was hoisted out of its previous wrapper.
- PopupBus initially called `current.visible = false` directly,
  which had no effect on popups whose `visible` was bound to a
  `popupOpen` property — Network/SystemStats/Weather/Media all use
  that pattern. Fix: PopupBus tracks the root Item and clears
  `popupOpen` instead, so the binding propagates the close.

---

## Step E4 — Shared `Surface` component

**Problem:** three near-identical card / pill patterns scattered
across every widget:
- Bar pill (`Rectangle { color: hover ? Theme.hot : "transparent"; radius: Theme.radius }`).
- Popup card (`Rectangle { color: Theme.bg; border.color: Theme.fg; border.width: 2; radius: Theme.radius }`).
- Overlay card (same as popup, bigger margins).

Plus notification toasts use `border.width: 1` + 18 %-alpha — a fourth
one-off variant.

**Goal:** one `Surface.qml` instantiated by every widget, so radius /
border / padding / opacity live in one place. After E3 the look is
locked in but the *implementation* still duplicates it — E4 dedupes.

**Plan:**

1. Inventory all `Rectangle { radius: Theme.radius … }` occurrences.
2. Three named variants:
   ```qml
   Surface { variant: "pill" }     // bar widgets, hover background
   Surface { variant: "popup" }    // calendar / weather / network
   Surface { variant: "overlay" }  // launcher / power-menu / pickers
   ```
3. Refactor each widget to use `Surface`. Bar widgets → `pill`;
   calendar / weather / network / bluetooth popups → `popup`; launcher
   / picker / power-menu → `overlay`; notification toast → also
   `popup` (drop the special border).
4. Register `Surface` in `qmldir`.

**Risk:** medium — touches every widget. Land incrementally, restart
quickshell after each, eyeball each widget.

**Verification:**

- Every widget renders identically before vs after — same colour,
  border, hover.
- `grep -c "radius: Theme.radius" ~/.config/quickshell/*.qml` drops
  to near zero.
- The diff in each widget: a `Rectangle { … }` block becomes a
  `Surface { variant: … }`.

---

## Step E5 — Wallpaper per theme (swaybg) ✅

**Problem:** swaybg currently shows a solid colour from Step 19. With
themes shipping wallpapers (after E1) we can have the wallpaper
follow `nirimaki-theme-set`.

**Goal:** `nirimaki-theme-set` picks the first image from the current
theme's `backgrounds/` and tells swaybg to display it. Theme swap →
wallpaper swap, no restart.

**Plan:**

1. Convention: each `themes/<name>/backgrounds/` has at least one
   image. The "active" one is either:
   - The first image alphabetically, OR
   - A `~/.config/theme/current/wallpaper` symlink the user can
     manually point elsewhere (used by E7's background picker).
2. `nirimaki-theme-set` after copying theme files:
   - Resolve the active wallpaper path.
   - `pkill swaybg` and `swaybg -i <path> -m fill &`.
3. niri's startup line (currently `spawn-sh-at-startup "swaybg -c
   #101315"`) becomes
   `spawn-sh-at-startup "swaybg -i $(readlink -f
   ~/.config/theme/current/wallpaper) -m fill"`, with the symlink
   pointing at the first image of the active theme by default.

**Risk:** if swaybg can't open the image (corrupt PNG?), no wallpaper
— but `swaybg -c #101315` is one shell command away as recovery.

**Verification:**

- `nirimaki-theme-set tokyo-night` → wallpaper changes to TN's shipped
  image.
- `nirimaki-theme-set default` → back to TN's image (it inherits whatever
  was set), unless `default` ships its own wallpaper — TBD if we want
  to ship one with `default`.

### Outcome

Built as part of E3.5 once the niri blur work made it clear that
the solid `#101315` swaybg was the reason no blur was visible.

- **`~/.local/bin/nirimaki-wallpaper-apply`** picks the first image
  (sorted) under `~/.config/theme/current/backgrounds/` and starts
  swaybg on it; falls back to a solid `#101315` if a theme ships no
  images (today: only the `default` theme).
- **niri** spawn-sh-at-startup calls the script in place of the
  old `swaybg -c "#101315"` line.
- **`nirimaki-theme-set`** calls it after every theme swap. Old swaybg
  is `pkill`d cleanly first so the new one binds to the same
  Wayland output.
- We deferred the planned `~/.config/theme/current/wallpaper`
  symlink (manual override): the picker overlay in E7 will own
  that selection mechanism, so it doesn't need to exist yet.

---

## Step E6 — Theme picker (Quickshell overlay) ✅

**Goal:** a `Mod+<key>` overlay that lists every available theme and
calls `nirimaki-theme-set` on enter — same UX as the Launcher / Power-Menu
/ Emoji picker.

**Plan:**

1. New `~/.config/quickshell/ThemePicker.qml` — overlay PanelWindow
   reusing the `Surface "overlay"` variant (post-E4).
2. Model = directories under `~/.config/theme/themes/`.
3. Each entry shows:
   - Theme name.
   - If a `themes/<name>/preview.png` exists, a small thumbnail.
   - Highlighted = current theme.
4. Up / Down / fuzzy filter; Enter spawns
   `nirimaki-theme-set <selected>` via `Quickshell.execDetached`. Live
   re-tint shows the theme without dismissing.
5. IPC `theme-picker` toggle handler. niri bind: `Mod+T` (already?
   check first) or something free.
6. Register in `qmldir`, instantiate in `shell.qml`.

**Risk:** none — just a new overlay reading the file tree.

**Verification:**

- Bind opens the picker; arrow keys cycle; Enter applies.
- Closing without Enter doesn't change theme.

### Outcome

- **`~/.config/quickshell/ThemePicker.qml`** — overlay PanelWindow
  styled like PowerMenu/EmojiPicker, reading the themes directory
  via `Qt.labs.folderlistmodel`.FolderListModel (so we don't shell
  out for `ls`).
- Header shows "Theme…" placeholder / current filter; rows show
  bullet glyph ( filled  for the active theme,  empty  for
  others) + theme name; selected row uses accent text on
  alpha(fg, 0.08) background — same look as the launcher's
  selected row.
- Picker seeds `selectedIndex` to the **currently-active theme**
  (looked up via `Theme.themeName`) so the menu opens "on" the
  current selection; arrow keys / fuzzy filter move from there.
- Enter calls
  `Quickshell.execDetached(["~/.local/bin/nirimaki-theme-set", name])`.
  Absolute path because Quickshell's spawn PATH doesn't include
  `~/.local/bin`. `nirimaki-theme-set` already triggers the full chain
  (Theme IPC reload, niri reload, swaybg restart, GTK/Qt gsettings).
- Mouse click on a row activates that theme.
- Namespace `nirimaki-theme-picker` so the existing layer surface rules
  apply (or don't — we have no layer-rule blur).
- **Initial bug:** missing `import QtQuick.Controls` — needed for
  `ScrollBar` on the ListView. Added.

**Wiring:**

- `qmldir`: `ThemePicker 1.0 ThemePicker.qml`
- `shell.qml`: `ThemePicker {}` added next to the other overlays.
- **niri keybind**: `Mod+Shift+T` spawns
  `quickshell ipc call -- theme-picker toggle`.

---

## Step E7 — Background picker (Quickshell overlay) ✅

**Goal:** mirror of E6 but for wallpapers within the current theme's
`backgrounds/`.

**Plan:**

1. New `~/.config/quickshell/BackgroundPicker.qml` — overlay reading
   `~/.config/theme/current/backgrounds/*.{png,jpg,jpeg,webp}`.
2. Grid (not list) with thumbnails — wallpapers are the whole point.
3. Enter on an entry:
   - Updates `~/.config/theme/current/wallpaper` symlink.
   - Restarts swaybg with the new image.
4. IPC `background-picker` toggle. niri bind: `Mod+Shift+W` or similar.

**Risk:** none.

**Verification:**

- Bind opens grid of thumbnails for the active theme.
- Arrow keys + Enter applies a new wallpaper instantly.
- Theme swap (`nirimaki-theme-set …`) resets to that theme's default
  wallpaper, which is then re-overrideable.

### Outcome

**Persistence layer:**

- `nirimaki-wallpaper-apply` resolution order changed:
    1. `~/.config/theme/current/wallpaper` symlink, if it resolves
       to a real file.
    2. First sorted image in `current/backgrounds/`.
    3. Solid `#101315` fallback (themes shipping no images).
- `nirimaki-theme-set` removes the `wallpaper` symlink before re-running
  `nirimaki-wallpaper-apply`, so each theme starts on its own first image
  and user-picked wallpapers don't bleed across themes.

**`~/.config/quickshell/BackgroundPicker.qml`** — grid of
thumbnails, same overlay UX as ThemePicker:

- Reads via `Qt.labs.folderlistmodel`.FolderListModel filtered to
  `*.jpg / *.jpeg / *.png / *.webp`.
- **Folder bound to the actual theme path**, not to
  `current/backgrounds`:
  `themes/<Theme.themeName>/backgrounds`. The `current/backgrounds`
  symlink swaps target on theme change without changing the URL,
  which FolderListModel doesn't pick up — using the resolved path
  makes the URL itself depend on `Theme.themeName`, so a theme
  swap refreshes the listing immediately.
- 4 columns × ~2 rows grid (card 1000 × 620). GridView width is
  pinned to `cardWidth - 2 * menuMargin` rather than
  `parent.width`, because Column doesn't stretch children
  horizontally — bind to parent.width was returning a smaller
  value and floor()-ing the column count down to 2.
  `cellWidth: Math.floor(width / columns)` guarantees `columns`
  cells fit exactly.
- Each cell: 16:9 thumbnail with 2px accent border when selected,
  filename stem below in fontPx. `sourceSize` is 2× the rendered
  size to keep thumbnails crisp without exploding memory.
- Up / Down move `±columns`; Left / Right move `±1`; Enter
  activates, type to fuzzy-filter, Esc dismisses.
- Activate writes the symlink + reruns the apply script in one
  shell call:
  `ln -sfn <path> ~/.config/theme/current/wallpaper && nirimaki-wallpaper-apply`
  (JSON-quoted via `JSON.stringify` for spaces / specials in paths).

**Wiring:**

- `qmldir`: `BackgroundPicker 1.0 BackgroundPicker.qml`.
- `shell.qml`: `BackgroundPicker {}` next to the other overlays.
- niri keybind: `Mod+Shift+B` →
  `quickshell ipc call -- background-picker toggle`.

**Cleanup that happened along the way:**

- Imported Omarchy theme `backgrounds/` directories shipped an
  `omarchy.png` brand image (one per theme, 20 of them). Restored
  the rest from a fresh `git clone basecamp/omarchy` and filtered
  the brand files out: `${base,,} == *omarchy*` skip in the copy
  loop. 65 wallpaper images kept, 20 dropped.

---

## Execution rules

- **One step per turn.** No interleaving across E1–E7.
- **niri config changes require `niri validate` before reload.**
- **Quickshell restart after every QML / template change.**
- **Backup before destructive ops.** Each step writes its own `.bak`;
  cleanup commands documented at the end of the step.
- **Theme swap test** at the end of each step that touches theme
  files — confirm `nirimaki-theme-set <each-of-three-themes>` still produces
  consistent output.
