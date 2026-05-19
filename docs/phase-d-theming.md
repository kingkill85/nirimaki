# Phase D — Visual consistency / theming

Goal: a single source of truth for every visual token used by the
shell, terminal, dotfile-themable apps, GTK apps, niri itself, and the
boot/lock flow — swappable in one command.

Inspired by basecamp/omarchy's theme system (every app's colours
template-rendered from a per-theme `colors.toml`), without the
"omarchy" branding in our paths.

---

## Step D1 — Theme directory layout + switcher

**Goal:** stand up the plumbing so the rest of Phase D has a place to
write into. No app actually reads from it yet — that happens in
[D2 onwards].

**Directory layout** under `~/.config/theme/`:

```
~/.config/theme/
├── current/             # active theme files — atomically swapped in.
│   ├── colors.toml      #   - foundational palette (accent / fg / bg /
│   │                    #     cursor / selection_* / color0..color15)
│   ├── shell.toml       #   - per-surface overrides
│   │                    #     (bar.*, popups.*, menu.*, notifications.*)
│   └── theme.name       #   - plain-text name of the current theme
└── themes/              # source themes; each subdir is a self-contained
    └── <name>/          # theme that gets copied into current/ by
        ├── colors.toml  # qs-theme-set.
        ├── shell.toml
        ├── btop.theme   #   - app-specific overrides land alongside,
        ├── icons.theme  #     picked up in later D steps.
        └── ...
```

Schema for `colors.toml` is a strict subset of Omarchy's
`themes/<name>/colors.toml` — their 19 upstream themes will drop in
verbatim once D2 wires the QML side up.

Schema for `shell.toml` mirrors the keys Omarchy's
`shell/Commons/Color.qml` looks up (`bar.background`, `popups.border`,
`menu.selected`, etc.) — same reason.

**Initial theme** at `themes/default/`: the values that were
hard-coded in `Theme.qml` through Phases A–C.
- background `#101315`, foreground / accent / cursor `#cacccc`
- 16-colour palette: muted monochrome with a single warm red `#a55555`
  for urgency. (Not used yet — picked up in D3 for kitty / btop.)

**Switcher scripts** under `~/.local/bin/`:

- `qs-theme-set <name>` — stages `~/.config/theme/next/`, copies the
  selected theme dir + writes `theme.name`, then atomic `mv` into
  `current/`. Refuses to switch if `colors.toml` is missing. App-restart
  hooks land in D3 (kitty, btop) and D7 (Plymouth) — not needed yet.
- `qs-theme-list` — prints every directory under `themes/` and marks
  the current one with `*`.

Both use `export PATH=…` at the top so they survive niri's spawn-PATH
gotcha if we later bind theme-cycle to a key
(see [[feedback-niri-spawn-path]]).

**Verification:**

```sh
qs-theme-list                  # → * default
qs-theme-set default           # → qs-theme-set: now using 'default'
ls ~/.config/theme/current/    # → colors.toml shell.toml theme.name
cat ~/.config/theme/current/theme.name
```

**No QML or app changes yet** — Theme.qml still has the same hard-coded
values, so visually nothing has changed. D2 wires the singleton to
read from `current/`.

---

## Step D2 — Live theme reload in Quickshell

**Goal:** wire `Theme.qml` to read its palette from
`~/.config/theme/current/{colors,shell}.toml`, and re-apply across every
widget when `qs-theme-set` swaps themes — no quickshell restart.

**Changes to `~/.config/quickshell/Theme.qml`:**

- Properties become regular (writable) `property` instead of
  `readonly` so `loadColors()` can update them. Defaults preserved as
  fallback values for the rare case the toml files are missing /
  malformed.
- `loadColors(raw)` parses the foundational keys (`foreground`,
  `background`, `accent`, `color1`, `cursor`) via a small regex —
  tolerates inline `# comments`, single or double quotes, trailing
  whitespace. Tiny TOML-ish parser; a real TOML lib would be overkill
  for "key = #rrggbb".
- `loadShell(raw)` flattens `[section] key = "value"` blocks into a
  `shellValues` map keyed `"section.key"`. Surface tokens are then
  reached via `pick(key, fallback)` so per-surface overrides cascade
  to foundational palette when absent.
- Derived tokens (`bgAlt`, `fgDim`, `hot`) bind to the foundational
  ones via `Qt.lighter / Qt.darker / Qt.rgba` so they auto-update
  whenever the source changes.
- `IpcHandler { target: "theme"; function reload() }` exposes a
  manual reload that `qs-theme-set` calls after writing the files.
  (See "Why explicit IPC" below.)
- `FileView { watchChanges: true }` kept as a fallback path for
  changes made outside `qs-theme-set` (e.g. editing colors.toml by
  hand). The inotify watch is fragile when the file is rewritten
  rapidly — explicit IPC handles the common case.

**Changes to `~/.local/bin/qs-theme-set`:**

- Stopped doing `rm -rf $CURRENT_DIR; mv $NEXT_DIR $CURRENT_DIR` —
  that destroyed the inode the FileView was watching, and the new
  file at the same path was invisible to `QFileSystemWatcher`.
- New approach: write each theme file into `current/` in place via
  `cp -f`, preserving inodes. Files that exist in `current/` but not
  in the new theme are removed explicitly so a stale `shell.toml`
  doesn't carry over.
- Tail of the script:
  ```sh
  quickshell ipc call -- theme reload >/dev/null 2>&1 || true
  ```
  Falls back silently if quickshell isn't running.

**Why explicit IPC instead of pure inotify:**

`cp -f` opens its destination for writing with `O_TRUNC`, fires
`IN_MODIFY` immediately (the file briefly exists at zero bytes), then
writes the new content and closes. QFileSystemWatcher's
`fileChanged` signal races against this — quickshell often saw the
empty file first and re-read nothing. Explicit IPC sidesteps the
race entirely.

**Gotcha hit during this step (logged here for future-me):**

`IpcHandler { ... }` cannot be a direct child of a singleton
`QtObject` — QtObject has no default child property and QML fails to
load with "Cannot assign to non-existent default property". Wrap it:

```qml
property IpcHandler _ipc: IpcHandler { … }
```

Same trick the FileViews use.

**Second theme shipped for verification:**
`~/.config/theme/themes/tokyo-night/colors.toml` is a verbatim copy of
basecamp/omarchy@master:themes/tokyo-night/colors.toml — confirms our
schema is wire-compatible with their upstream themes.

**Verification:**

```sh
quickshell ipc show | grep -A1 target | grep theme  # → target theme
qs-theme-set tokyo-night                            # bar turns blue
qs-theme-set default                                # bar back to monochrome
```

The swap is instant — within ~50 ms of the script's exit the entire
bar / popups / workspace pills / OSD / launcher all re-tint.

---

## Step D3 — Per-app templates (kitty + btop)

**Goal:** generate `kitty.conf` and `btop.theme` from the active
`colors.toml` so the terminal palette and btop dashboard track every
`qs-theme-set`.

**Templates** under `~/.config/theme/templates/` — verbatim ports of
basecamp/omarchy@master:`default/themed/*.tpl`. `{{ key }}` is the raw
hex (`#cacccc`); `{{ key_strip }}` drops the leading `#`;
`{{ key_rgb }}` produces a decimal `r,g,b` tuple. The substitutions are
built into a sed script in `qs-theme-set` from `current/colors.toml`.

**Output paths:**
- `~/.config/theme/current/kitty.conf` — `~/.config/kitty/kitty.conf`
  picks it up via `include`. `qs-theme-set` sends `SIGUSR1` to running
  kitty processes so the swap is live.
- `~/.config/btop/themes/qs.theme` — written directly into btop's
  fixed lookup dir.
- `~/.config/btop/btop.conf` — pre-written with `color_theme = "qs"`
  so the first btop launch is already themed. btop merges this with
  its baked-in defaults for keys we don't set, so we only own the
  two lines we care about.

**Why not swaylock template:** initially we templated a
`swaylock.conf.tpl` too, but it turned out the user wanted an actual
visible password entry box — which swaylock doesn't render (only an
indicator ring). Replaced wholesale in D4.

---

## Step D4 — Quickshell-native lock screen

**Goal:** replace the indicator-only swaylock with a real
password-entry lock screen styled to match the rest of the shell.

**False starts (recorded so we don't relive them):**

1. **gtklock.** Installed `gtklock` (AUR) + GTK CSS template under
   `~/.config/theme/templates/gtklock.css.tpl`. It rendered a
   password entry but its GTK4-CSS surface area is awkward — every
   tweak fought defaults somewhere else. Removed after D4 landed.
2. **`swaylock --debug` to "test" the templated config** ran
   actual `swaylock` from a tool context. That's a no-op `timeout 1`
   away from locking the user out — and twice during this session
   that's what happened. Lesson: **never run a locker from this
   assistant context**; only the user triggers locks.

**Final solution:** standalone Quickshell config at
`~/.config/quickshell/lock/`:

```
shell.qml         ShellRoot { WlSessionLock { ... } }
LockContext.qml   PamContext + currentText buffer + signals
LockSurface.qml   centred clock+date, password card matching PowerMenu
Theme.qml         duplicate of the main shell's singleton so the lock
                  process is self-contained
qmldir            registers Theme, LockContext, LockSurface
pam/              vestigial — see "PAM gotcha" below
```

niri keybinds use the explicit path form so the locker survives the
"top-level `shell.qml` exists → no subdir scan" rule in quickshell's
config discovery:

```kdl
spawn-sh-at-startup "swayidle -w … 'quickshell -p /home/michael/.config/quickshell/lock/shell.qml' …"
Super+Alt+L { spawn "quickshell" "-p" "/home/michael/.config/quickshell/lock/shell.qml"; }
```

`PowerMenu.qml` Lock entry takes the same argv.

**Gotchas hit while landing this** (all real lockouts on the way —
TTY recovery `Ctrl+Alt+F2` → `pkill -f 'quickshell.*lock'` is the
back-pocket plan whenever this surface area changes):

- **Subdir configs are ignored when `shell.qml` exists at the
  Quickshell root.** Quickshell's docs cover it — if
  `~/.config/quickshell/shell.qml` is present, the "named config"
  subdir mode is disabled. Workaround: `-p <absolute path>` instead
  of `-c <name>`.
- **`qmldir` must list every sibling type explicitly.** Without
  `LockContext 1.0 LockContext.qml` etc., `shell.qml` fails with
  `LockContext is not a type`. The minimal `singleton Theme …` we
  had wasn't enough — adding a qmldir for the singleton appears to
  disable implicit sibling resolution.
- **`PamContext.configDirectory` is resolved from CWD, not from the
  shell config dir.** Passing `"pam"` as a relative path makes PAM
  look in `$HOME/pam/`, not `~/.config/quickshell/lock/pam/`. Easiest
  fix is to skip our custom config entirely and reuse the system's
  `login` service (the same stack gtklock/sddm authenticate against),
  via:
  ```qml
  PamContext { config: "login" }
  ```
- **`auth include system-auth` doesn't work standalone.** It uses
  `pam_unix.so try_first_pass`, which expects an earlier module in
  the stack to have stored a password. Called bare, every attempt
  fails. `auth include login` is the right include for an interactive
  prompt — same indirection gtklock uses.
- **Always reference signal-handler context explicitly.** In
  `PamContext.onPamMessage`, write `pam.respond(...)` rather than
  `this.respond(...)`; `this` in QML signal handlers is unreliable.

**Cleanup:**

- `paru -Rns gtklock` (uninstall package).
- `rm -f ~/.config/theme/templates/gtklock.css.tpl ~/.config/theme/current/gtklock.css`.
- `qs-theme-set`'s "don't sweep these rendered outputs" allow-list
  drops `gtklock.css`.
- `~/.config/swaylock/` already removed in the swaylock → gtklock
  transition (Step D3 interlude).

---

## Step D5 — GTK theme + icons + dark/light hot-swap

**Goal:** every GTK app and the freedesktop color-scheme portal track
the active theme. Switching `qs-theme-set` flips Nautilus / GNOME
Settings / file dialogs from dark to light in real time.

**Per-theme files** (mirroring `basecamp/omarchy@master:themes/<name>/`):
- `icons.theme` — single line, the GTK icon theme name. Omarchy uses
  Yaru variants tinted to the palette (`Yaru-blue`, `Yaru-purple`,
  `Yaru-magenta`, …). On Arch the package is `yaru-icon-theme` from
  AUR; install via `paru -S yaru-icon-theme`.
- `light.mode` — **presence** marks a light theme. Absent → dark.
  Mirrors Omarchy's marker exactly (we briefly used a `mode` text
  file instead; switched to presence-test for direct compatibility).

**`qs-theme-set` GTK block** at the end of the script:
- Reads `~/.config/theme/current/light.mode` → decides `prefer-light`
  vs `prefer-dark` and `Adwaita` vs `Adwaita-dark`.
- Reads `~/.config/theme/current/icons.theme` (default fallback
  `Yaru-blue`).
- Runs three `gsettings set org.gnome.desktop.interface ...` calls:
  `color-scheme`, `gtk-theme`, `icon-theme`. Portal-aware libadwaita
  apps re-tint live; GNOME shell tracks `color-scheme`.
- Mirrors the same values into `~/.config/gtk-3.0/settings.ini` and
  `~/.config/gtk-4.0/settings.ini` (idempotent `sed -i`) for apps that
  bypass the portal.

**Initial themes shipped** under `~/.config/theme/themes/`:

| Theme | Mode | icons.theme | Notes |
|-------|------|-------------|-------|
| `default` | dark | `Yaru-blue` | matches Phase A-C hard-coded palette |
| `tokyo-night` | dark | `Yaru-purple` | Omarchy ships `Yaru-magenta` for this theme; user preferred purple (closer to TN's `color5 #ad8ee6` / `color13 #bb9af7` while still distinct from default) |
| `catppuccin-latte` | light | `Yaru-blue` | verbatim port of Omarchy's; touches `light.mode` to flip everything to light on swap |

**Verification:**

```sh
qs-theme-set tokyo-night        # bar + apps re-tint, icons turn purple
qs-theme-set catppuccin-latte   # full light flip
qs-theme-set default            # back to mono-dark
gsettings get org.gnome.desktop.interface color-scheme
gsettings get org.gnome.desktop.interface icon-theme
```

Nautilus may need a one-time relaunch the first time icons change
(icon cache is rebuilt on next start). Older GTK3 apps without portal
support also need a relaunch.

### D5 gotcha — `Adwaita-dark` is not a theme on stock Arch

First pass set `gtk-theme-name=Adwaita-dark`; Remmina (and any other
GTK3 app without libadwaita) stayed light despite all the gsettings /
settings.ini hits. Root cause: `Adwaita-dark` is a separate theme
that ships with the `gnome-themes-extra` package — without it,
`/usr/share/themes/Adwaita-dark/` doesn't exist and GTK silently
falls back to the compiled-in (light) Adwaita.

**Fix (modern path, no extra packages):** keep `gtk-theme-name=Adwaita`
always and let dark/light flip via the
`gtk-application-prefer-dark-theme` flag + freedesktop color-scheme
portal. Both `settings.ini` files + the `qs-theme-set` GTK block now
do that. The `Adwaita-dark` name is deprecated for GTK3.20+ anyway.

### Remmina has its own dark switch

Remmina ignores the GTK theme and reads `dark_theme=<bool>` from
`~/.config/remmina/remmina.pref`. `qs-theme-set` now also sed-rewrites
that line to mirror `light.mode`, so Remmina follows the active theme.
Needs a Remmina restart per swap.

---

## Step D5b — Qt apps (qt5ct + qt6ct)

**Goal:** every Qt app uses the active theme's palette + icon theme,
flipping dark / light with `qs-theme-set`.

**Install:** `paru -S qt5ct qt6ct` (qt5ct is AUR on Arch; qt6ct is in
extra). `yaru-icon-theme` from D5 covers the icon side.

**Static configs** (written once):
- `~/.config/qt6ct/qt6ct.conf` — `style=Fusion`, `custom_palette=true`,
  `color_scheme_path=/home/michael/.config/theme/current/qt-colors.conf`,
  `icon_theme=Yaru-blue` (rewritten by qs-theme-set on each swap).
- `~/.config/qt5ct/qt5ct.conf` — identical, separate path.

**Template:** `~/.config/theme/templates/qt-colors.conf.tpl` renders a
Qt color-scheme INI with three rows of 21 `#aarrggbb` colours
(active / inactive / disabled) keyed off the foundational palette in
`colors.toml`. Lands at
`~/.config/theme/current/qt-colors.conf`; both qt5ct and qt6ct read it.

**qs-theme-set** adds a per-swap `sed -i "s|^icon_theme=…"` on each
`qt*ct.conf` to keep the icon theme synced with GTK.

**Niri `environment` block** gets `QT_QPA_PLATFORMTHEME "qt6ct"` so
every spawned Qt app picks up the platform theme module. Qt5 apps
also honor this if qt6ct isn't found at runtime, otherwise they fall
through to `~/.config/qt5ct`.

**Caveats:**
- Already-running Qt apps don't see the new env var; only freshly
  spawned ones do (niri config reload affects spawn, not extant
  children).
- Some Qt apps draw their own widgets ignoring qt5ct/qt6ct (KDE apps
  with their own theming, Telegram, etc.) — those will need
  per-app overrides if/when they appear.

**Verification:**

```sh
QT_QPA_PLATFORMTHEME=qt6ct kate          # opens dark
QT_QPA_PLATFORMTHEME=qt6ct qbittorrent   # opens dark
qs-theme-set catppuccin-latte && QT_QPA_PLATFORMTHEME=qt6ct kate  # opens light
```

---

## Step D6 — xdg-desktop-portal dialogs themed

**Goal:** verify the file picker, screencast/screenshare picker, and
the permissions dialog all follow the active theme.

**Outcome:** no work needed beyond D5 — the portal layer was already
correctly wired by Arch defaults + the gsettings changes we made.

**What was checked:**

- `/usr/share/xdg-desktop-portal/niri-portals.conf` ships with niri:

  ```ini
  [preferred]
  default=gnome;gtk;
  org.freedesktop.impl.portal.Access=gtk;
  org.freedesktop.impl.portal.Notification=gtk;
  org.freedesktop.impl.portal.Secret=gnome-keyring;
  ```

  So FileChooser / ScreenCast / ScreenShot go to
  `xdg-desktop-portal-gnome` (with `…-gtk` as fallback), Access +
  Notification go to `…-gtk`. Both backends are installed
  (`xdg-desktop-portal-{gnome,gtk}` packages).

- The portal correctly reports our dark preference:

  ```sh
  gdbus call --session --dest org.freedesktop.portal.Desktop \
       --object-path /org/freedesktop/portal/desktop \
       --method org.freedesktop.portal.Settings.Read \
       org.freedesktop.appearance color-scheme
  # → (<<uint32 1>>,)   (1 = prefer-dark)
  ```

  `qs-theme-set <name>` flips that value because it sets
  `org.gnome.desktop.interface color-scheme` via gsettings, which the
  portal exposes verbatim.

- **Verification by inspection:** opening Nautilus shows a dark
  libadwaita window; in-Nautilus dialogs (Open With…, file picker
  inside other apps) also render dark.

**No changes landed in this step — it was a verify-only milestone.**

---

## Step D7 — Plymouth bootsplash (blank + centred password field)

**Goal:** replace the bare cryptsetup CLI prompt at boot with a dark
blank screen + a centred password entry — same visual feel as the
shell's lock screen.

**Pre-existing system state worth recording:**

- Boot loader: **limine** (`/boot/limine/limine.conf`).
- Initramfs format: **Unified Kernel Image** at
  `/boot/EFI/Linux/arch-linux.efi`. Kernel cmdline lives in
  `limine.conf`, not in the UKI.
- Root: BTRFS on a LUKS volume (`nvme1n1p2`,
  `UUID=46a9c349-4548-4503-92d7-e24d0d8a2088`).
- No fallback UKI shipped by default — `linux.preset` had
  `PRESETS=('default')` only.

### Safety step first — enable the fallback UKI

Before touching anything boot-critical, generate a fallback image so a
broken main UKI still leaves a recovery path. `/etc/mkinitcpio.d/linux.preset`
now uses:

```
PRESETS=('default' 'fallback')
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

`mkinitcpio -P` builds both UKIs. Added a second entry to
`/boot/limine/limine.conf` pointing at the fallback EFI. Cmdline on
the fallback entry is the same LUKS+rootfs cmdline as main but
without `quiet splash` — so any failure surfaces directly on TTY.

Verified by rebooting and selecting "Arch Linux (fallback)" once
before continuing.

### First attempt — `plymouth-encrypt` (didn't work on Arch)

Standard wiki advice for Plymouth + non-systemd initramfs is to swap
the `encrypt` hook for `plymouth-encrypt`. On current Arch the
plymouth package ships only the `plymouth` and `plymouth-shutdown`
hooks — no `plymouth-encrypt`. mkinitcpio errored with:

```
==> ERROR: Hook 'plymouth-encrypt' cannot be found
```

That path is effectively retired in favour of the systemd-based
initramfs.

### Real solution — switch to systemd-based initramfs

**HOOKS** in `/etc/mkinitcpio.conf`:

```
HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

- `systemd` replaces `udev` — needed so the in-initramfs systemd
  units (including the Plymouth password agent) come up.
- `plymouth` after `systemd` so plymouthd is owned by it.
- `sd-vconsole` replaces `keymap` + `consolefont` — same job, but
  driven by `/etc/vconsole.conf` via the systemd unit.
- `sd-encrypt` replaces `encrypt` — talks to the Plymouth password
  agent natively so the LUKS prompt is rendered by our theme.

**Cmdline change** (`limine.conf` main entry):

```
- cryptdevice=PARTUUID=9c992b53-…:root  (old encrypt-hook syntax)
+ rd.luks.name=46a9c349-4548-4503-92d7-e24d0d8a2088=root  (sd-encrypt syntax)
```

…with `quiet splash` appended. Fallback entry kept the same hook
chain (rebuilt with the same HOOKS) but without `quiet splash`, so
recovery still surfaces kernel messages on TTY.

### Plymouth theme — `qs-minimal`

A stripped port of Omarchy's `default/plymouth/omarchy.script` — no
logo, no lock icon, no progress bar. Just:

- Dark background `(0.063, 0.075, 0.082)` (= Theme default `#101315`)
- A centred entry PNG (`entry.png`) borrowed verbatim from Omarchy.
- Up to 21 bullet-dot PNGs (`bullet.png`, scaled to 7×7) drawn inside
  the entry as the user types.

Files live under `/usr/share/plymouth/themes/qs-minimal/`:
- `qs-minimal.plymouth` — manifest pointing at the script.
- `qs-minimal.script` — show/hide logic + bullet placement.
- `entry.png`, `bullet.png` — visual assets.

Activated via `sudo plymouth-set-default-theme qs-minimal && sudo
mkinitcpio -P` so the theme is baked into the UKI.

**Why the colours are hard-coded:** Plymouth runs *before* `sd-encrypt`
unlocks the disk, so `~/.config/theme/current/colors.toml` isn't
readable yet. Live `qs-theme-set` swaps don't propagate to the boot
splash; updating boot colours requires editing the script + rebuilding
the UKI.

### Lockout recovery, just in case

If the main UKI ever stops booting:

1. At the limine menu pick **"Arch Linux (fallback)"** — bare cryptsetup
   CLI prompt, no plymouth, full kernel boot messages.
2. From a working shell: `sudo plymouth-set-default-theme bgrt`
   (the upstream default) and `sudo mkinitcpio -P` to drop the custom
   theme.
3. Or boot Arch USB → `arch-chroot`, edit limine.conf to remove
   `splash`, rebuild UKI.

### Cleanup left for later

Backup files written along the way (all small, kept for quick rollback):

```
/etc/mkinitcpio.conf.bak               pre-plymouth HOOKS line
/etc/mkinitcpio.d/linux.preset.bak     pre-fallback (PRESETS=('default'))
/boot/limine/limine.conf.bak           pre-fallback-entry
/boot/limine/limine.conf.bak2          pre-splash
```

Delete after a week or two of confidence:

```sh
sudo rm /etc/mkinitcpio.conf.bak /etc/mkinitcpio.d/linux.preset.bak \
        /boot/limine/limine.conf.bak /boot/limine/limine.conf.bak2
```

---

## Step D9 — Branding identity (Nirimaki logo, UKI splash, plymouth visuals)

**Goal:** give the project a name, a wordmark, and a coherent visual
identity from very-early boot (UKI splash) → Plymouth → desktop. Up
to this step the setup was "an Omarchy-style niri install"; from D9
onwards it is **Nirimaki** — niri + *maki* (rolled sushi), mirroring
how Omarchy = *omakase* (chef's-choice) + Arch.

### D9.1 — Wordmark + assets layout

ASCII wordmark generated via
[patorjk.com/software/taag](http://patorjk.com/software/taag/) — DHH's
own recommendation for Omarchy-style logos. Block-character font, no
shadow corners. Source-of-truth at `~/niri-setup/assets/logo.txt`
after a small hand-edit.

A pure-pixel renderer at `~/niri-setup/scripts/ascii2png.sh` converts
the ASCII to a transparent PNG by drawing each `█`/`▀`/`▄`/`▌`/`▐`
cell as a rectangle. Avoids the kerning / line-height seams that any
font-based approach produces with block-drawing glyphs.

```sh
# Cell 48 px wide × 144 px tall → vertically-stretched wordmark suitable
# for boot logo use (~2500 × 1000)
~/niri-setup/scripts/ascii2png.sh \
  ~/niri-setup/assets/logo.txt \
  ~/niri-setup/assets/logo.png 48 144
```

Ten colour variants derived from the white canonical via
`magick … +level-colors` (Tokyo Night accent palette):

```sh
for spec in white:'#ffffff' salmon:'#f7768e' orange:'#ff9e64' \
            amber:'#e0af68'  wasabi:'#9ece6a' teal:'#73daca'  \
            cyan:'#7dcfff'   blue:'#7aa2f7'   lavender:'#bb9af7' \
            magenta:'#ad8ee6'; do
  name="${spec%%:*}"; hex="${spec#*:}"
  magick ~/niri-setup/assets/logo.png \
    -channel RGB +level-colors "$hex","$hex" \
    ~/niri-setup/assets/logo-$name.png
done
```

`logo-palette.png` is a stacked comparison sheet used to pick the
canonical accent.

**Canonical Nirimaki accent: `#e0af68` (amber).**

### D9.2 — Replace the Arch UKI splash

The "Arch Linux" wordmark that flashes briefly *before* Plymouth comes
from `systemd-stub`: mkinitcpio embeds an image into a `.splash` PE
section in the UKI, which the stub draws via the EFI graphics
protocol. Default source on Arch is
`/usr/share/systemd/bootctl/splash-arch.bmp`. Confirm with:

```sh
objdump -h /boot/EFI/Linux/arch-linux.efi | grep splash
# .splash section, ~378 KB, embedded directly in the EFI binary
```

Replacement BMP — **24-bit, no alpha, pure-black background** so it
blends with the firmware's black clear (any non-black background
shows up as a visible rectangle around the logo):

```sh
magick ~/niri-setup/assets/logo-amber.png \
  -resize 800x -background "#000000" -alpha remove -alpha off \
  BMP3:~/niri-setup/assets/splash.bmp
```

Install + rewire the preset + rebuild:

```sh
sudo install -Dm644 ~/niri-setup/assets/splash.bmp \
  /usr/share/nirimaki/splash.bmp

sudo cp /etc/mkinitcpio.d/linux.preset{,.bak}
sudo sed -i \
  's|/usr/share/systemd/bootctl/splash-arch.bmp|/usr/share/nirimaki/splash.bmp|' \
  /etc/mkinitcpio.d/linux.preset

sudo mkinitcpio -P
```

Only the **default** UKI carries `--splash`; the fallback (per D7) is
deliberately spartan, so even a broken splash can't lock you out.

**Aside on BGRT:** The firmware-stored BGRT (Boot Graphics Resource
Table) at `/sys/firmware/acpi/bgrt/image` is a separate, even earlier
flash — on this machine it is a 409×307 "PRO SERIES" motherboard
manufacturer logo, not Arch. Replacing it would require a BIOS-level
reflash with a vendor tool. To suppress it instead, prepend
`bgrt_disable` to the `cmdline` line(s) in `/boot/limine/limine.conf`.

### D9.3 — Logo + progress bar in Plymouth (`qs-minimal`)

Extends the D7 theme with the upstream Omarchy visuals it intentionally
left out: a centred logo above the entry, plus the fake/real progress
bar that fills while LUKS is being unlocked.

Assets added under `/usr/share/plymouth/themes/qs-minimal/`:

| File | Source |
|------|--------|
| `logo.png` | `~/niri-setup/assets/logo-amber.png`, resized to 800 wide |
| `progress_box.png` | Copied verbatim from `basecamp/omarchy/default/plymouth/`. **Kept at original `#292E42`** — recolouring it to the fg makes box and bar indistinguishable, hiding all visible progress. (Matches omarchy's own `omarchy-plymouth-set`, which only recolours `progress_bar`/`bullet`/`entry`/`lock`, never the box.) |
| `progress_bar.png` | Copied verbatim from omarchy, recoloured to `#cacccc` via `magick … +level-colors '#cacccc','#cacccc'` to match the entry foreground |

Script changes vs the D7 version (full file mirrored at
`~/niri-setup/assets/qs-minimal.script`):

- New `logo.image / logo.sprite` block, vertically centred on the
  window.
- `entry.y` now anchors below the logo
  (`logo.sprite.GetY() + logo.image.GetHeight() + 40`) instead of
  centring on the window.
- New globals + `refresh_callback` driving a 50 FPS animation that
  ramps fake progress to **70 % over 15 s** with an ease-out-quad
  curve.
- `display_normal_callback` shows the bar in `boot`/`resume` mode once
  a password has been seen (`global.password_shown == 1`).
- `display_password_callback` stops fake progress, hides the bar,
  shows entry + bullets.
- `progress_callback` (`Plymouth.SetBootProgressFunction`) hands the
  real LUKS progress over to the bar once it overtakes the fake value
  — `update_progress_bar` ratchets, never moves backwards.

The progress bar shares the entry's vertical slot, so the screen
never displays both at once: bar while waiting, entry while typing,
bar again once the password is accepted.

Install + safety backup of the previous script:

```sh
sudo cp /usr/share/plymouth/themes/qs-minimal/qs-minimal.script{,.bak2}
sudo install -m644 ~/niri-setup/assets/logo-amber.png \
  /usr/share/plymouth/themes/qs-minimal/logo.png
sudo install -m644 ~/niri-setup/assets/progress_box.png \
  /usr/share/plymouth/themes/qs-minimal/progress_box.png
sudo install -m644 ~/niri-setup/assets/progress_bar.png \
  /usr/share/plymouth/themes/qs-minimal/progress_bar.png
sudo install -m644 ~/niri-setup/assets/qs-minimal.script \
  /usr/share/plymouth/themes/qs-minimal/qs-minimal.script
sudo mkinitcpio -P
```

### D9.4 — Layout under `~/niri-setup/`

```
niri-setup/
├── assets/
│   ├── logo.txt                  ASCII source-of-truth (edit this)
│   ├── logo.png                  white-on-transparent master (rendered)
│   ├── logo-{white,salmon,orange,amber,wasabi,teal,
│   │         cyan,blue,lavender,magenta}.png    10 colour variants
│   ├── logo-palette.png          stacked comparison sheet
│   ├── splash.bmp                24-bit BMP3 for the UKI .splash section
│   ├── qs-minimal.script         plymouth script mirror of /usr/share copy
│   └── progress_box.png, progress_bar.png   recoloured omarchy assets
└── scripts/
    └── ascii2png.sh              ASCII → transparent PNG renderer
```

### D9.5 — Re-running the pipeline

When `logo.txt` is edited (or you want a different cell size / accent),
the full chain to push to all sinks:

```sh
# 1. Rasterise the ASCII (square or stretched; here 48 × 144)
~/niri-setup/scripts/ascii2png.sh \
  ~/niri-setup/assets/logo.txt \
  ~/niri-setup/assets/logo.png 48 144

# 2. Recolour into all variants (loop from D9.1)
# 3. Boot splash BMP (resize + flatten on black)
magick ~/niri-setup/assets/logo-amber.png \
  -resize 800x -background "#000000" -alpha remove -alpha off \
  BMP3:~/niri-setup/assets/splash.bmp

# 4. Push assets to the live theme + rebuild UKIs
sudo install -Dm644 ~/niri-setup/assets/splash.bmp \
  /usr/share/nirimaki/splash.bmp
sudo install -m644 ~/niri-setup/assets/logo-amber.png \
  /usr/share/plymouth/themes/qs-minimal/logo.png
sudo mkinitcpio -P
```

### D9.6 — New backups & cleanup

Backups written in this step (in addition to the D7 set):

```
/etc/mkinitcpio.d/linux.preset.bak           pre-Nirimaki-splash path
/usr/share/plymouth/themes/qs-minimal/qs-minimal.script.bak
                                              pre-logo (D7 original)
/usr/share/plymouth/themes/qs-minimal/qs-minimal.script.bak2
                                              pre-progress-bar (D9.3)
```

Delete after a week or two of confidence:

```sh
sudo rm /etc/mkinitcpio.d/linux.preset.bak \
        /usr/share/plymouth/themes/qs-minimal/qs-minimal.script.bak \
        /usr/share/plymouth/themes/qs-minimal/qs-minimal.script.bak2
```

---

## Phase D complete

Every Phase-D item shipped:

- ✅ D1 — Theme directory layout + switcher (`qs-theme-set`/`-list`).
- ✅ D2 — Quickshell `Theme.qml` reads `colors.toml`+`shell.toml`,
  reloads via IPC.
- ✅ D3 — kitty + btop templates rendered per theme.
- ✅ D4 — Quickshell-native lock screen (replaced swaylock + gtklock).
- ✅ D5 — GTK + icon + dark/light hot-swap (Adwaita + Yaru icon
  variants, `prefer-dark`/`prefer-light` via gsettings).
- ✅ D5b — Qt 5/6 platform palette via qt5ct/qt6ct.
- ✅ D6 — xdg-desktop-portal dialogs (file picker, screencast picker,
  permission dialogs) themed automatically by D5.
- ✅ D7 — Plymouth bootsplash on the Omarchy entry+bullet visuals,
  systemd-based initramfs, with a fallback UKI safety net.
- ⏭  D8 — Light/dark toggle widget (tried, reverted: doesn't make
  sense when most themes don't come in light/dark twins; swapping
  themes by name is the working flow).
- ✅ D9 — Nirimaki branding pass: ASCII wordmark + render pipeline,
  amber colour variant, UKI `.splash` replacement, plymouth logo +
  fake/real progress bar.
- [ ] **D6** — xdg-desktop-portal share picker themed via D5.
- [ ] **D7** — Plymouth: blank background + centred swaylock-style
  password prompt.
- [ ] **D8** — light/dark toggle + bar widget.
- [ ] **D4** — niri visual tweaks (focus ring, gaps, swaybg colour) sourced
  from theme.
- [ ] **D5** — GTK + icon + cursor + `color-scheme` via gsettings/ini.
- [ ] **D6** — xdg-desktop-portal share picker themed via D5.
- [ ] **D7** — Plymouth: blank background + centred swaylock-style password
  prompt.
- [ ] **D8** — light/dark toggle + bar widget.
