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
| Bins  | `bitwarden` (desktop UI) + `bitwarden-cli` (`bw` CLI for scripting) — both Arch official |
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
