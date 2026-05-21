# Phase F — Internationalization + keybind consolidation

Two unrelated cleanups bundled into one phase because both are
about *making the system speak with one voice*: i18n unifies user-
facing strings under a single dictionary; keybind consolidation
unifies the input map under a single config file.

## Step targets

| Step | Topic | What changes |
|------|-------|--------------|
| **F1** | i18n singleton | New `I18n.qml`, JSON dictionaries, locale detection |
| **F2** | Translation files | `i18n/en.json` (canonical), `i18n/de.json` |
| **F3** | QML sweep | Every hardcoded user-facing string → `I18n.t(key)` |
| **F4** | Verify i18n | Run Quickshell under `LANG=de_DE.UTF-8` vs `LANG=en_US.UTF-8` |
| **F5** | Keybind audit | Inventory all current binds + niri's defaults; flag conflicts |
| **F6** | `keybinds.kdl` extraction | Move binds out of `config.kdl` into included file, grouped |
| **F7** | Picker hotkey display | Quickshell pickers show "Mod+Shift+T" in their header (reads `keybinds.kdl`) |

---

## Step F1 — `I18n.qml` singleton ✅

**Plan:**

1. `~/.config/quickshell/I18n.qml`, a `pragma Singleton` `QtObject`
   exposing:
   - `property string locale` — resolved at startup from
     `Quickshell.env("LC_MESSAGES")` ∥ `LANG` ∥ Qt.locale().name,
     normalised to short form (`de_DE.UTF-8` → `de`).
   - `property var dict` — flat key→string map loaded from
     `i18n/<locale>.json`.
   - `property var fallbackDict` — loaded from `i18n/en.json` so
     missing keys fall back to English rather than rendering empty.
   - `function t(key)` — returns `dict[key] ?? fallbackDict[key] ??
     key`. Last fallback is the key itself so an untranslated
     string at least shows what it is.
2. Both files loaded via `FileView`. `watchChanges: true` so
   editing a translation hot-reloads without restarting Quickshell.
3. Register as `singleton I18n 1.0 I18n.qml` in `qmldir`.

**Risk:** none — additive only.

**Verification:**

- `quickshell ipc call -- i18n ping` returns `"ok"` (add an
  IpcHandler so we can sanity-check load state).
- Edit `i18n/de.json`, observe a re-tinted bar pill within a
  frame.

---

## Step F2 — Initial translation files ✅

**Plan:**

1. `~/.config/quickshell/i18n/en.json` is the canonical key list.
   Categories prefix the key (`launcher.placeholder`,
   `power.action.lock`, `weather.feels`).
2. `~/.config/quickshell/i18n/de.json` translates the same keys.
3. Initial scope (auditable in F3, but plan up-front so we don't
   miss anything in the dictionary):
   - Picker headers: `launcher.placeholder`, `theme.placeholder`,
     `background.placeholder`, `power.placeholder`,
     `emoji.placeholder`, `clipboard.placeholder`.
   - Power-menu action labels: `power.action.{lock,suspend,logout,
     restart,shutdown}`.
   - Search placeholders: `launcher.search` ("Search applications…"),
     `clipboard.empty` ("Clipboard is empty"),
     `emoji.empty` ("No matches for …" — split into prefix + arg).
   - Weather labels: `weather.feels`, `weather.wind`, `weather.humidity`.
   - Network labels: `network.disconnected`, `network.ip`,
     `network.gateway`, `network.link`, `network.ethernet`.
   - SystemStats labels: `stats.system`, `stats.cpu`,
     `stats.memory`, `stats.load`.
   - Calendar header: row/column abbreviations stay locale-driven via
     `Qt.locale()` (already i18n'd implicitly by Qt) — no entries
     needed.

**Risk:** keys we forget at this stage will fall back to the raw
key in non-English locales. Easy to add later.

**Verification:**

- `jq . < en.json` parses cleanly.
- `jq . < de.json` parses cleanly.
- Diff `keys-only` should produce empty output (parity check).

---

## Step F3 — QML sweep ✅

**Plan:**

1. Grep every QML file for user-facing string literals (`text:
   "…"`, placeholder Text, header labels). Skip technical strings
   (icon glyphs, format codes, IPC target names).
2. Replace each with `text: I18n.t("category.key")`.
3. For strings with runtime interpolation (`"No matches for \""
   + filter + "\""`), use a two-arg form:
   `I18n.t("emoji.empty", filter)` where the singleton does
   `string.replace("{0}", arg)`.
4. Touch files: Launcher, ThemePicker, BackgroundPicker,
   EmojiPicker, ClipboardPicker, PowerMenu, Network, Weather,
   SystemStats, Media, NotificationToast, PamContext (lock screen
   prompt).

**Risk:** typos in keys turn into visible "category.key" tokens
in the UI. Mitigated by the fallback-to-key behaviour catching
exactly that, plus a sanity grep at the end.

**Verification:**

- `grep -nE 'text:\s*"[A-Z]' ~/.config/quickshell/*.qml` returns
  only known-fine strings (glyphs, formats).
- Visually open each overlay with `LANG=de_DE.UTF-8` and confirm
  German rendering.

---

## Step F4 — Verify i18n end-to-end ✅

**Plan:**

- Restart quickshell under `LANG=en_US.UTF-8` → all strings
  English.
- Restart under `LANG=de_DE.UTF-8` → all strings German.
- Live-edit `de.json`, observe hot-reload.

**Risk:** locale resolution failing silently → everything looks
English. The `I18n.locale` property exposed via IPC will tell us
what was actually loaded.

### Outcome (F1–F4)

- **`~/.config/quickshell/I18n.qml`** — `pragma Singleton` `QtObject`.
  `locale` resolved from `LC_MESSAGES` → `LANG` → `Qt.locale().name`,
  normalised to the 2/3-letter language code. `dict` + `fallbackDict`
  loaded via `FileView` (watchChanges) from `i18n/<locale>.json` and
  `i18n/en.json`. `t(key, arg)` returns
  `dict[key] ?? fallbackDict[key] ?? key`, with `{0}` interpolated
  from `arg`. IPC handler `target: "i18n"` exposes `ping`, `locale`,
  `reload` for debugging.
- **Lazy-singleton gotcha**: QML singletons don't instantiate until
  something accesses them, so the I18n IpcHandler didn't register
  until a widget used `I18n.t(...)`. `shell.qml` now contains a
  throwaway `QtObject { property string _eager: I18n.locale }` to
  force instantiation at shell startup. Once F3 wired `I18n.t(...)`
  into every widget the eager touch became redundant but harmless.
- **`~/.config/quickshell/i18n/en.json` + `de.json`** — 29 keys
  each, same key set verified via diff. Categories: `launcher.*`,
  `theme.*`, `background.*`, `emoji.*`, `clipboard.*`, `power.*`
  (placeholder + 5 action labels), `network.*`, `stats.*`,
  `weather.*`, `lock.*`.
- **QML sweep** touched Launcher, ThemePicker, BackgroundPicker,
  EmojiPicker, ClipboardPicker, PowerMenu, Network, SystemStats,
  Weather. PowerMenu actions changed from `{label: "Lock"}` to
  `{labelKey: "power.action.lock"}` with `I18n.t(labelKey)` at
  render time, so switching locale re-tints labels without
  rebuilding the action list. Weather's local 7-language `tr()`
  table dropped — replaced with `I18n.t("weather.feels")` /
  `wind` / `humid` driven by the JSON dictionaries.
- **Lock screen deferred.** `lock/shell.qml` runs as a separate
  Quickshell process with its own qmldir, so it can't reach the
  main config's `I18n` singleton. The "Falsches Passwort" string
  stays hardcoded (it's already German, which matches this user's
  system) with a TODO comment. Sharing I18n with the lock screen
  is a symlink-or-copy decision for later.

---

## Step F5 — Keybind audit

**Plan:**

1. Dump every bind in `~/.config/niri/config.kdl` `binds { … }`
   block — should be ~50–80 lines of binds plus the niri-defaults.
2. Group them by category (mental model for F6):
   - **App launchers**: terminal, browser, launcher, pickers,
     power menu, dictation.
   - **Window management** (niri-native): focus, move, workspace,
     overview, fullscreen, close, layout presets.
   - **Output / monitor**: focus monitor, move column to monitor.
   - **Media keys / OSD**: volume, mute, brightness, play/pause.
   - **System actions**: screenshot, screen-record, lock,
     keyboard-shortcut inhibit, quit.
3. Flag duplicates and any bind missing
   `hotkey-overlay-title="…"`.

**Risk:** none — read-only audit. Output kept in this MD file.

---

## Step F6 — `keybinds.kdl` extraction ✅

**Plan:**

1. New `~/.config/niri/keybinds.kdl` containing exactly one
   `binds { … }` block, grouped by category from F5.
2. Each bind keeps its `hotkey-overlay-title` so niri's built-in
   Mod+Shift+/ overlay groups them sensibly.
3. `~/.config/niri/config.kdl` replaces its in-place `binds { … }`
   block with
   `include "/home/michael/.config/niri/keybinds.kdl"`.
4. `niri validate` after every save.

**Risk:** broken bind syntax during the move → no input. Mitigated
by validating before reloading, and the existing config is one
`git stash` away (we'll back the file up as `.bak` first).

**Verification:**

- `niri msg action load-config-file` reloads cleanly.
- Every bind still works (run through the category list).
- Mod+Shift+/ shows the same bindings as before.

### Outcome

**`~/.config/niri/keybinds.kdl`** — single `binds { … }` block
grouped under category headers (help, app launchers, pickers,
dictation, system actions, screenshot / recording, volume, media,
brightness, overview, focus, move, monitor, workspace, by-index,
mouse wheel, layout, universal clipboard). `config.kdl` lost its
in-line binds block and gained
`include "/home/michael/.config/niri/keybinds.kdl"` plus a backup
at `config.kdl.bak`. Every XF86 / brightness bind got a
`hotkey-overlay-title` so they show up labelled in Mod+Shift+/.

**Omarchy parity adds + reshuffles** (per user direction):

- Apps adopt Omarchy's Super+Shift+&lt;letter&gt; pattern. Added:
    - `Mod+Return` → terminal alias (`Mod+T` kept)
    - `Mod+Shift+Return` + `Mod+Shift+B` → browser alias
      (`Mod+B` kept)
    - `Mod+Shift+F` → nautilus
- `Mod+Space` → launcher alias; `Mod+Ctrl+Space` → background
  picker; `Mod+Shift+Ctrl+Space` → theme picker — all from the
  Omarchy `_Space` family. Background picker no longer aliased on
  `Mod+Shift+B` (collided with the new browser launch).
- `Mod+Escape` → power menu. The previous `Mod+Escape` action
  (`toggle-keyboard-shortcuts-inhibit`) was removed: it's silent
  unless an inhibitor-aware client is focused, and the user
  doesn't run RDP / KVM.
- `Ctrl+Alt+Delete` (`quit`) removed — power menu's Logout covers
  ending the session.
- `hotkey-overlay { skip-at-startup }` set so niri stops popping
  the cheat sheet at login.

**Universal clipboard (`Mod+C / V / X`)** — Omarchy's trick:
`wtype` injects `Ctrl+Insert` / `Shift+Insert` / `Ctrl+X` into the
focused window. Every sane app (browsers, GTK, vim, …) treats
those as Copy / Paste / Cut. The displaced niri actions move:
`center-column` → `Mod+Alt+C`; `center-visible-columns` →
`Mod+Shift+C`; `toggle-window-floating` → `Mod+Alt+V`;
`fullscreen-window` → `Mod+Alt+F` (`Mod+Shift+F` is now nautilus).

**kitty workaround** — kitty doesn't bind `Ctrl+Insert` /
`Shift+Insert` by default, so wtype's injection landed but kitty
ignored it. Mirrored Omarchy's fix in `~/.config/kitty/kitty.conf`:

```
map ctrl+insert  copy_to_clipboard
map shift+insert paste_from_clipboard
```

`Mod+Ctrl+V` is also bound to the clipboard history (Omarchy's
"Clipboard manager"), aliasing `Mod+Y`.

---

## Step F7 — Quickshell keybind sheet (replaces niri's overlay) ✅

**Goal:** a proper Quickshell overlay that lists every keybind
parsed from `keybinds.kdl`, grouped by the same category headers
the file already uses (App launchers, Pickers, Clipboard, Focus,
…). Same look as the other overlays (Launcher / ThemePicker /
BackgroundPicker). Replaces niri's built-in Mod+Shift+/ sheet,
which is informationally fine but visually inconsistent with the
rest of the shell.

**Plan:**

1. New `~/.config/quickshell/KeybindSheet.qml` — PanelWindow
   overlay, scrim + bordered card, search/filter, two columns:
   key combo on the left, action description on the right.
2. Source data: parse `keybinds.kdl` from QML. Each `===== <name>
   =====` comment becomes a section header. Each bind line is
   parsed for:
    - The key chord (everything before the first space / `{`).
    - The `hotkey-overlay-title="…"` if present (preferred label),
      otherwise the niri action name from the body
      (`{ close-window; }` → `close-window`).
3. Filter input narrows by chord OR description (case-insensitive
   substring match).
4. Trigger: `quickshell ipc call -- keybind-sheet toggle`. Niri
   binds: `F1` (universal help key — same physical position and
   xkb name on every keyboard layout, unlike `/` which moves
   around between DE / US / FR / etc.) and `Mod+Shift+/`
   (replaces the niri built-in `show-hotkey-overlay`, kept for
   muscle memory).
5. Register in `qmldir`, instantiate in `shell.qml`.

**Risk:** KDL is a structured format; a careless regex parser will
mis-handle multi-line spawn bodies (the screenshot bind has a
`spawn-sh` block spanning multiple lines). Keep the parser
line-oriented but track brace depth so multi-line entries don't
get split mid-body. If the parser turns into a tarpit, fall back
to having a helper script emit JSON for QML to consume.

**Verification:**

- Mod+Shift+/ opens the Quickshell sheet, not niri's overlay.
- Mod+K does the same.
- Section headers match `keybinds.kdl` categories.
- Filtering by "browser" surfaces both `Mod+B` and `Mod+Shift+B`.
- Esc dismisses without firing any bind.

### Outcome

**Big keybind reshuffle landed alongside F6 / F7** after the user
called out duplicates and re-anchored on Omarchy convention:

- **Apps (Omarchy `Mod+Shift+<letter>` family):** `Mod+Return` =
  terminal, `Mod+Space` = launcher, `Mod+Shift+B` = browser,
  `Mod+Shift+E` = file explorer (nautilus). All previous niri-
  default aliases (`Mod+T` / `Mod+B` / `Mod+D` / `Mod+Y`,
  `Mod+E`, `Mod+Shift+T` for theme, `Mod+Shift+F` for nautilus,
  …) removed.
- **Pickers (Omarchy `Mod+Ctrl+<key>` family):** `Mod+Ctrl+V` =
  clipboard, `Mod+Ctrl+E` = emoji, `Mod+Ctrl+Space` = background,
  `Mod+Shift+Ctrl+Space` = theme, `Mod+Escape` = power menu.
- **Window-management HJKL family fully consistent**: every action
  has both arrows AND HJKL on the same modifier prefix —
  `Mod+` = focus, `Mod+Ctrl+` = move column, `Mod+Alt+` = monitor
  focus, `Mod+Ctrl+Alt+` = move column to monitor. `Mod+Shift+*`
  reserved exclusively for app launches.
- **Lock screen** moved to `Ctrl+Alt+L`. `Super+Alt+L` aliased to
  `Mod+Alt+L` at runtime, which is now `focus-monitor-right`.
- **System keys** `Mod+F1` = keybind sheet (Mod+F1 not bare F1,
  because F1 / F9 are commonly used by apps), `Mod+F9` =
  dictation toggle.
- Bind count: 129 → 122 → 138 (post-HJKL-consistency).

**`~/.config/quickshell/KeybindSheet.qml`** — the overlay itself:

- `FileView` reads `~/.config/niri/keybinds.kdl` with
  `watchChanges: true`, so editing the file hot-reloads the
  sheet on next open.
- Parser is a line-by-line walk that tracks brace depth so
  multi-line `spawn-sh` bodies (the screenshot bind) don't get
  re-parsed mid-body. Each `// ===== <Section> =====` comment
  becomes a section header; each bind line yields a `{chord,
  label}` pair where `label` prefers
  `hotkey-overlay-title="…"` and falls back to the niri action
  name from the body.
- Two-column delegate (chord left, label right) with section
  headers in accent. Filter matches against chord, label, or
  section name — so typing `browser` surfaces every browser
  bind, typing `wheel` filters down to the mouse-wheel section.
- Niri's built-in `show-hotkey-overlay` is no longer bound;
  the sheet has full ownership of `Mod+F1` (the user picked it
  for universal-keyboard friendliness — bare `F1` shadows
  apps; `/` moves around between layouts).

---

## Lock screen polish (out-of-plan, done in F7 sweep)

Done because the user asked for them mid-F7. Logging here so the
phase file matches reality.

- **i18n on the lock screen.** `lock/qmldir` gained `singleton
  I18n 1.0 I18n.qml`; `lock/I18n.qml` and `lock/i18n` are
  symlinks to `../I18n.qml` and `../i18n` so the dictionaries
  stay in one place. `lock/LockSurface.qml` uses
  `I18n.t("lock.password")` for the placeholder and
  `I18n.t("lock.bad_password")` for the failure message. Two
  new keys in `en.json` + `de.json`.
- **Wallpaper background.** `LockSurface` now renders the same
  image swaybg displays: an `Image` with
  `source: "file://" + HOME + "/.config/theme/current/wallpaper"`
  and `fillMode: Image.PreserveAspectCrop`, plus a 55 %-black
  scrim on top so the centred password card stays readable
  against any image. `Theme.bg` is still the outer fallback if
  the symlink ever breaks.
- **`nirimaki-theme-set` bugfix.** Previously the theme swap removed
  the `wallpaper` symlink so each theme could start on its own
  first image. That broke the lock screen's `Image` source
  after every swap. Fix: instead of removing the symlink, point
  it at the new theme's first image (alphabetical first of
  `current/backgrounds/*.{jpg,jpeg,png,webp}`). The symlink is
  always valid; BackgroundPicker can still rewrite it.
- **Password field UX**: input is now centre-aligned
  (`horizontalAlignment: TextInput.AlignHCenter`) so the
  placeholder sits in the middle of the field instead of
  hugging the left edge, and `font.letterSpacing: 4` spaces
  the typed bullets out so they read as separate dots.

---

## My recommended order

F1 → F2 → F3 → F4   (i18n done, English+German shipping) ✅
F5 → F6             (keybinds consolidated, behaviour changes folded in) ✅
F7                  (Quickshell sheet — replaces the niri overlay)
