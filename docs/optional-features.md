# Optional features

Stuff that isn't part of the baseline install but slots into Nirimaki
cleanly. Each is gated behind one menu pick (or one `nirimaki <feature>
install` from the CLI). All install/remove scripts share the same UX:
banner with Nirimaki logo, single sudo prompt at the start (cached for
the rest of the script), no yes/no confirmation noise, final pause so
you can read the result.

The **state-aware menu** hides entries that don't apply:
- `Install → <feature>` disappears once `<feature>` is installed
- `Remove → <feature>` only appears for features that are installed

State lives in `~/.cache/nirimaki/state.json`, refreshed by
`nirimaki-hook-run` after every `*-installed` / `*-removed` event (and
re-seeded at session start by `niri spawn-at-startup`).

---

## Voxtype — voice dictation

| Where | `Install / Remove → AI → Voxtype` |
|-------|-----------------------------------|
| Bins  | `wtype` (Arch official) + `voxtype-bin` (AUR via paru/yay) |
| Model | Whisper `base` multilingual, ~150 MB, auto-downloaded |
| Hotkey | `Mod+F9` toggles record / transcribe |
| Config | `~/.config/voxtype/config.toml` — language defaults to `"auto"` so English/German/etc. mix transparently |
| Service | Systemd **user** unit `voxtype.service` (auto-enabled on install) |
| Persistence | Reboots — service stays enabled, model files in `~/.local/share/voxtype/` |

GPU acceleration auto-enabled if Vulkan is detected (`vulkaninfo
--summary` returns a GPU). Pin a single language with `language = "de"`
in the config for slightly better accuracy than `auto`.

---

## Stream Deck — Elgato hardware control

| Where | `Install → Stream Deck` (CLI: `nirimaki streamdeck install`) |
|-------|-------------------------------------------------------------|
| Engine | [`deckmaster`](https://github.com/muesli/deckmaster) (AUR) — headless daemon that owns USB-HID + key image rendering |
| Access | uaccess udev rule `/etc/udev/rules.d/99-nirimaki-streamdeck.rules` (no root) |
| Editor | GUI: `Settings → Setup → Stream Deck` — the `streamdeck-editor` panel plugin (only loads when deckmaster is installed). The key grid auto-sizes to the connected model (`nirimaki-streamdeck-detect` maps the USB product id → cols×rows: Mini 3×2, Original/MK.2 5×3, XL 8×4, +/Neo 4×2; falls back to saved `cols`/`rows` or 5×3 offline). The "Launch app" action chooses from installed apps (same `DesktopEntries` source as the launcher); footer has **Restart** + **Save & apply** |
| Config | `~/.config/nirimaki/streamdeck.json` — friendly JSON the editor reads/writes; works from the shipped sample out of the box |
| Lifecycle | `nirimaki-streamdeck.service` (systemd **user** unit, `assets/systemd/`) owns the daemon: starts at login, stops at logout, and `Restart=on-failure` relaunches deckmaster if it crashes. There is no niri-autostart line — the unit replaces it |
| Recovery | If the deck goes dark: the editor's **Restart** button, or `nirimaki streamdeck restart` (start-from-dead; the editor is reachable whenever deckmaster is *installed*, even when not running) |
| Re-theme | Activate `~/.config/nirimaki/hooks/theme-set.d/streamdeck-reload.sample` (drop `.sample`, `chmod +x`) for live recolor on theme switch |

The GUI editor (`plugins/builtin/streamdeck-editor/`) is a lazy
`panel` plugin with `requires.binary: deckmaster`, so it's only
summonable when the daemon is installed — and the Setup menu entry is
`visibleWhen` the `streamdeck` feature is installed. It edits in-memory
and persists on **Save** via `nirimaki-streamdeck-set` (validate → write
→ reload). 5×3 key grid, per-key action editor, page add/delete,
brightness slider.

**Why a wrapper, not deckmaster directly:** deckmaster's native config
is low-level TOML and its `recentWindow`/`keycode` widgets are X11-only
(dead on niri). `nirimaki-streamdeck-generate` compiles our JSON into
per-page `.deck` files under `~/.cache/nirimaki/streamdeck/`, mapping
high-level action `type`s onto `exec` actions over the existing
`nirimaki` CLI + `niri msg action` (which work on Wayland), and pulls
key colors from `~/.config/theme/current/colors.toml`.

Action `type`s: `webapp` (launch-or-focus via `nirimaki-streamdeck-focus-app`),
`mic-mute`, `volume`, `theme`, `workspace`, `niri`, `exec`, `app`,
`page` (deck switch), `status` (`time` / `top` cpu·memory / `command`
widgets). Keys: index 0–14, left-to-right, top-to-bottom.

`nirimaki-streamdeck-start` forces `~/.local/bin` onto `PATH` before
exec'ing deckmaster — otherwise its `exec` key actions couldn't find the
`nirimaki*` helpers (gotcha #1). niri imports `WAYLAND_DISPLAY` /
`NIRI_SOCKET` / DBus into the systemd `--user` environment, so the unit's
`niri msg` key actions resolve correctly.

Icons are validated in `nirimaki-streamdeck-generate`: it strips
Quickshell's `image://icon/` prefix and emits a key icon **only** when it
resolves to a readable raster file (png/jpg/…). deckmaster aborts on an
icon it can't open — which would blank the whole deck — so unresolved
icons are dropped and the key falls back to its text label.

Tested against the Stream Deck **Original V2** (`0fd9:006d`, 15 keys).
Other Elgato models share VID `0fd9`, so the udev rule + deckmaster
cover them, and the editor grid auto-sizes to the detected model. The
shipped sample layout assumes 15 keys, but indices beyond a smaller
deck's key count simply don't render on that hardware.

**Not yet:** per-theme icon *tinting* (deckmaster places icons
un-tinted; v1 leans on themed label `color` + the `time`/`top`
`fillColor`). Set an absolute `"icon"` path on any key (or via the
editor's "Icon path" field) to use your own image.

---

## Tailscale — mesh VPN

| Where | `Install / Remove → Service → Tailscale` |
|-------|------------------------------------------|
| Bins  | `tailscale` (Arch official) |
| Service | Systemd **system** unit `tailscaled.service` |
| Auth  | One-time browser flow during install (URL printed in foot) |
| Persistence | **Reboots — yes, fully.** `tailscaled` starts on boot via `systemctl enable`, credentials in `/var/lib/tailscale/` are read by the daemon on start, the tunnel comes up automatically. Re-auth only if you `tailscale logout` or your session token expires (default ~6 months, configurable per device in the admin console). |
| Bonus | Registers the [Tailscale admin console](https://login.tailscale.com/admin/machines) as a Chromium webapp (live-themed like everything else). |

---

## Bitwarden — password manager

| Where | `Install / Remove → Service → Bitwarden` |
|-------|------------------------------------------|
| Bins  | `bitwarden` (desktop UI, extra/) + `bitwarden-cli-bin` (`bw` CLI, AUR). The CLI is the AUR prebuilt rather than extra/`bitwarden-cli` because the latter pins `nodejs-lts-jod`, which conflicts with the rolling `nodejs` and would force a system-wide Node downgrade. The `-bin` SEA binary has no Node dep. Needs an AUR helper (paru/yay); if absent, only the desktop app installs. |
| Persistence | Encrypted vault stays in `~/.config/Bitwarden/` even after remove. Re-install picks up where you left off; nuke that dir manually if you really want a clean slate. |
| Window rule | Floats by default + blocked from screen capture (covered by the same niri rule as 1Password / KeePassXC). |

---

## Steam — gaming client + lib32 stack

| Where | `Install / Remove → Gaming → Steam` |
|-------|-------------------------------------|
| Bins  | `steam` + `lib32-mesa` + `lib32-vulkan-icd-loader` + matching `lib32-vulkan-<vendor>` (or `lib32-nvidia-utils`) |
| GPU detection | `lspci` decides vendor (AMD / Intel / NVIDIA) — installs the right Vulkan ICD only |
| Multilib | Auto-enables `[multilib]` in `/etc/pacman.conf` if not already on |
| Persistence | Reboots — yes. `/etc/pacman.conf` change persists; Steam's game library, screenshots, controller config under `~/.local/share/Steam/` all persist across remove → reinstall too. |
| Window rules | Steam main pinned 1100×700, Friends List 460×800, always opaque, floats by default. |
| **Not installed** | Proton-GE, MangoHud, gamescope — `paru -S` whichever you want. |
| Removal | `pacman -Rns steam` only; `lib32-*` stays (other apps may depend on it post-install), `[multilib]` stays enabled (same reason). |

---

## VS Code

| Where | `Install / Remove → Editor → VS Code` |
|-------|---------------------------------------|
| Bins  | `visual-studio-code-bin` (AUR — the Microsoft build with the proprietary marketplace) |
| Defaults written | `~/.vscode/argv.json` (`password-store: gnome-libsecret`) + `~/.config/Code/User/settings.json` (`update.mode: none` — pacman/paru manage updates) |
| Set as `$EDITOR` | `Setup → Default editor → VS Code` (only appears once VS Code is installed) |
| Persistence | Settings + extensions stay in `~/.config/Code/` after remove. Re-install resumes the same workspace. |

---

## Helix

| Where | `Install / Remove → Editor → Helix` |
|-------|--------------------------------------|
| Bin   | `hx` (Arch official `helix` package) |
| Defaults written | `~/.config/helix/config.toml` seeded with relative line numbers, mouse, bufferline, indent guides (skipped if you already have a config) |
| Set as `$EDITOR` | `Setup → Default editor → Helix` |

---

## Common helpers

### `nirimaki-feature-state`

Single source of truth for "is this feature installed?". Emits
`~/.cache/nirimaki/state.json`:

```json
{
  "voxtype": true,
  "tailscale": false,
  "bitwarden": true,
  "steam": true,
  "helix": false,
  "vscode": false,
  "zed": false,
  "nvim": true,
  "_updated": "<iso8601>"
}
```

SettingsMenu FileView-watches it; the install/remove filter rebuilds
on every change. Run manually via `nirimaki feature state` (e.g. after
a `pacman -S` outside the menu) to refresh.

### `nirimaki-feature-prelude`

Sourced library every install/remove script begins with. Provides
`nirimaki_banner` (logo + title bar) / `nirimaki_sudo_prime`
(one-prompt sudo + background refresher) / `nirimaki_pause` (final
"Press Enter to close…"). See [phase-j-platform.md](phase-j-platform.md)
for the template.

### `nirimaki-gaming-gpu-lib32`

Reusable helper called by `nirimaki-steam-install` (and any future
gaming installs — Lutris, Heroic, …). Auto-picks `lib32-vulkan-*`
matching the GPU vendor detected via `lspci`. Hidden from
`nirimaki help` because it's not meant to be invoked directly.

---

## Adding a new optional feature

Template walkthrough lives in
[phase-j-platform.md § "Optional-feature install/remove wrapper"](phase-j-platform.md).
Summary: ~50 lines of bash per feature (install + remove + optional
status) + 2 JSON menu nodes + 2 i18n strings + add the feature name
to `nirimaki-feature-state`. The state filter and the unified CLI
pick it up automatically.
