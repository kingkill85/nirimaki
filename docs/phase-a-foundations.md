## Step 1 — Multi-monitor output config

**Goal:** make niri drive all three monitors at their max refresh rate, with
VRR enabled, in the physical layout the user actually has on their desk.

**Detected hardware** (from `niri msg outputs`):

| Connector | Make/Model              | Mode used         |
|-----------|-------------------------|-------------------|
| DP-1      | Acer VG270U P (27")     | 2560x1440@143.856 |
| DP-2      | Iiyama PL2783Q (27")    | 2560x1440@69.923  |
| DP-3      | AOC 24G15N (24")        | 1920x1080@180.003 |

**Physical layout:**
- Acer DP-1 = primary, in front of user
- AOC DP-3 = stacked above the Acer, horizontally centered over it
- Iiyama DP-2 = right side, rotated 90° counter-clockwise (portrait),
  vertically centered against the Acer

**Logical coordinates (all scale 1):**
- AOC: `position x=320 y=0` (320 = (2560-1920)/2 to center over Acer)
- Acer: `position x=0 y=1080` (directly below AOC)
- Iiyama (rotated): `position x=2560 y=600` (centered on Acer vertically)
- Iiyama gets `transform "90"` → logical size becomes 1440x2560
- All three get `variable-refresh-rate`

**Change applied to `~/.config/niri/config.kdl`:**

Replace the stock commented-out example block:

```kdl
/-output "eDP-1" {
    // …default example content…
    mode "1920x1080@120.030"
    scale 2
    transform "normal"
    position x=1280 y=0
}
```

with these three real blocks:

```kdl
// Acer VG270U P (27" 1440p 144Hz) — primary, in front of user
output "DP-1" {
    mode "2560x1440@143.856"
    scale 1
    transform "normal"
    position x=0 y=1080
    variable-refresh-rate
}

// AOC 24G15N (24" 1080p 180Hz) — stacked above Acer, centered horizontally
output "DP-3" {
    mode "1920x1080@180.003"
    scale 1
    transform "normal"
    position x=320 y=0
    variable-refresh-rate
}

// Iiyama PL2783Q (27" 1440p) — right side, portrait (90° CCW), centered on Acer
output "DP-2" {
    mode "2560x1440@69.923"
    scale 1
    transform "90"
    position x=2560 y=600
    variable-refresh-rate
}
```

**Verification:**

```sh
niri msg outputs | grep -E '^Output|Current mode|Variable refresh|Logical position|Logical size|Transform'
```

Expected lines per output:
- DP-1: `Current mode: 2560x1440 @ 143.856 Hz`, `Variable refresh rate: supported, enabled`, `Logical position: 0, 1080`, `Transform: normal`
- DP-2: `Current mode: 2560x1440 @ 69.923 Hz`, `Variable refresh rate: supported, enabled`, `Logical position: 2560, 600`, `Logical size: 1440x2560`, `Transform: 90° counter-clockwise`
- DP-3: `Current mode: 1920x1080 @ 180.003 Hz`, `Variable refresh rate: supported, enabled`, `Logical position: 320, 0`, `Transform: normal`

**Notes / caveats:**
- niri auto-reloads the config on save — no manual reload needed.
- Outputs matched by connector name; will break if monitors get moved to
  different DP ports. Can be re-matched by `Make Model Serial` later if needed.
- Iiyama overhangs the Acer by 40 px top and bottom (Iiyama 2560 tall vs Acer
  1440 + 1080 px AOC overlap math). Cursor crosses to the Iiyama in the y
  range [600, 3160].

---

## Step 2 — Core CLI tools + AUR helper + browser

**Goal:** install the tools the default niri config already calls out
(`playerctl`, `brightnessctl`), an AUR helper (`paru`), and the user's
preferred browser (Zen Browser).

**Commands (run interactively — sudo will prompt for password):**

```sh
# Official-repo packages: media-key tool, brightness tool, build prerequisites for AUR
sudo pacman -Syu --needed playerctl brightnessctl base-devel git rust

# Build & install paru from AUR source (NOT paru-bin — see gotcha below)
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru
makepkg -si

# AUR install: Zen Browser
paru -S zen-browser-bin
```

**Gotcha encountered:** `paru-bin` (the prebuilt-binary variant) is linked
against `libalpm.so.14`, but current Arch ships `libalpm.so.15`. Result:
`paru: error while loading shared libraries: libalpm.so.15: cannot open
shared object file`. Fix is to use source `paru` (which compiles against
the local libalpm).

If `paru-bin` was already installed, remove it AND its debug split package
before installing source `paru`, otherwise file conflicts ensue:

```sh
sudo pacman -Rns paru-bin paru-bin-debug
```

**Rust vs rustup:** picked `rust` (system toolchain from the official repo
— works immediately, no `rustup default stable` step). `rustup` would only
matter if doing real Rust development with multiple toolchains.

**Verification:**

```sh
pacman -Q playerctl brightnessctl rust paru zen-browser-bin
command -v playerctl brightnessctl paru zen-browser
```

Expected — each name resolves to `/usr/bin/<name>` and pacman shows a
version per package.

**Versions at time of install (2026-05-18):**

| Package         | Version       |
|-----------------|---------------|
| playerctl       | 2.4.1-5       |
| brightnessctl   | 0.5.1-3       |
| rust            | 1:1.95.0-1    |
| paru            | 2.1.0-2       |
| zen-browser-bin | 1.19.13b-1    |

**Cleanup (optional):**

```sh
rm -rf /tmp/paru
```

---

## Step 3 — Make Zen the default browser + add `Mod+B` keybind

**Goal:** route all `xdg-open`/web-link clicks to Zen, and bind `Mod+B` in
niri so the browser can be launched without a launcher.

**Set Zen as the xdg default:**

```sh
xdg-settings set default-web-browser zen.desktop
```

This already populates the core scheme handlers in `~/.config/mimeapps.list`.

**Augment `~/.config/mimeapps.list`** so all common HTML / browser-related
MIME types route to Zen. Final `[Default Applications]` section:

```ini
[Default Applications]
x-scheme-handler/claude-cli=claude-code-url-handler.desktop
text/html=zen.desktop
x-scheme-handler/http=zen.desktop
x-scheme-handler/https=zen.desktop
x-scheme-handler/about=zen.desktop
x-scheme-handler/unknown=zen.desktop
x-scheme-handler/chrome=zen.desktop
application/xhtml+xml=zen.desktop
application/x-extension-htm=zen.desktop
application/x-extension-html=zen.desktop
application/x-extension-shtml=zen.desktop
application/x-extension-xhtml=zen.desktop
application/x-extension-xht=zen.desktop
```

(`x-scheme-handler/claude-cli` entry pre-existed and is preserved.)

**Add `Mod+B` keybind** in `~/.config/niri/config.kdl`, right after the
existing `Mod+T` (kitty) bind:

```kdl
Mod+B hotkey-overlay-title="Open Zen Browser" { spawn "zen-browser"; }
```

Also fixed a default-config typo while there: `Mod+T`'s hotkey-overlay-title
said "alacritty" but spawned `kitty`. Corrected to "kitty".

**Verification:**

```sh
xdg-settings get default-web-browser              # → zen.desktop
xdg-mime query default x-scheme-handler/https     # → zen.desktop
xdg-mime query default text/html                  # → zen.desktop
```

Then press `Mod+B` in niri — Zen should launch.

---

## Step 4 — Full Noto font coverage (CJK / emoji / extra scripts)

**Goal:** stop tofu boxes for Chinese / Japanese / Korean, emoji, and
less-common scripts (Arabic, Hebrew, Thai, Indic, etc.). Baseline `noto-fonts`
only ships Latin/Cyrillic/Greek-class scripts.

**Command:**

```sh
sudo pacman -S --needed noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
fc-cache -f
```

Restart any already-running GUI apps (kitty, Zen) so they pick up the new
fonts. Niri itself doesn't need a restart.

**Verification:**

```sh
pacman -Q noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
fc-match emoji                    # → NotoColorEmoji.ttf: "Noto Color Emoji"
fc-match "sans:lang=ja"           # → NotoSansCJK-Regular.ttc
fc-match "sans:lang=zh"           # → NotoSansCJK-Regular.ttc (with JP-style glyphs, see caveat)
```

**Versions installed (2026-05-18):**

| Package          | Version           |
|------------------|-------------------|
| noto-fonts-cjk   | 20240730-1        |
| noto-fonts-emoji | 1:2.051-1         |
| noto-fonts-extra | 1:2026.05.01-1    |

**Caveat — regional glyph preference (not fixed in Step 4):**

`fc-match "sans:lang=zh"` resolves to "Noto Sans CJK **JP**" rather than
"Noto Sans CJK **SC**". The CJK glyphs all render (Chinese is no longer tofu)
but with Japanese-style forms — subtly wrong for native Chinese readers.
Same issue for Korean (resolves to JP instead of KR). To fix, add a
fontconfig preference snippet in `~/.config/fontconfig/conf.d/`. Deferred
for now.

---

## Step 5 — Fontconfig regional preference for CJK

**Goal:** make `lang=zh` pages render with Simplified Chinese (SC) glyphs and
`lang=ko` pages render with Korean (KR) glyphs, instead of the Noto CJK
default which is JP for both. Japanese (`lang=ja`) is unchanged.

**Change:** new file `~/.config/fontconfig/conf.d/99-noto-cjk-regional.conf`.
Prefixed `99-` so the rules apply after Noto's own conf files and override
the default JP preference via `mode="prepend" binding="strong"`.

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Chinese (zh, zh-cn, zh-tw, zh-hk all default to SC) -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh</string></test>
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans CJK SC</string>
    </edit>
  </match>
  <!-- …same pattern for serif → Noto Serif CJK SC,
       monospace → Noto Sans Mono CJK SC… -->

  <!-- Korean (ko, ko-kr) -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>ko</string></test>
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans CJK KR</string>
    </edit>
  </match>
  <!-- …same pattern for serif → Noto Serif CJK KR,
       monospace → Noto Sans Mono CJK KR… -->
</fontconfig>
```

(Full file on disk has all six match blocks — sans/serif/mono × zh/ko.)

After writing, refresh and restart fontconfig-using apps:

```sh
fc-cache -f
```

**Verification:**

```sh
fc-match "sans:lang=zh"      # → "Noto Sans CJK SC"
fc-match "serif:lang=zh"     # → "Noto Serif CJK SC"
fc-match "monospace:lang=zh" # → "Noto Sans Mono CJK SC"
fc-match "sans:lang=ko"      # → "Noto Sans CJK KR"
fc-match "sans:lang=ja"      # → "Noto Sans CJK JP" (unchanged)
```

**Notes:**

- `compare="contains"` on lang catches all region tags (`zh`, `zh-cn`,
  `zh-tw`, `zh-hk` all route to SC). If TC (Traditional, for Taiwan) or HK
  glyphs become wanted later, add more-specific `<test><string>zh-tw</string>`
  rules below the bare-`zh` rules in the same file — later prepends win.
- Restart any running GUI app (Zen, kitty) to pick up the new preference.

---

## Step 6 — Minimal kitty config

**Goal:** kill the Wayland CSD title bar at the top of kitty windows, and
stop the "are you sure?" prompt on close. Nothing else changed.

**New file `~/.config/kitty/kitty.conf`:**

```conf
# Drop the Wayland CSD title bar.
# Niri's focus ring will sit around the window edges instead.
hide_window_decorations yes

# Don't confirm on Ctrl+Shift+Q / window close.
confirm_os_window_close 0
```

**Verification:** close all existing kitty windows, then re-launch
(`Mod+T`). The window should have no top title bar; pressing `Ctrl+Shift+Q`
or closing the window should exit immediately without a confirmation
dialog.

**Note:** `hide_window_decorations` only takes effect for *new* kitty
processes — already-running windows keep their old decorations until
restarted.

**Alternative (not used here):** instead of fixing CSD per app, you can
uncomment `prefer-no-csd` in `~/.config/niri/config.kdl`. That asks *all*
apps to drop their CSD, which is the niri-recommended setup — but it also
removes title bars from Zen and other apps that might want them. Per-app
config is more conservative.

---

## Step 7 — Monitor refinement: VRR + reposition Iiyama

**Goal:** enable variable refresh rate on all three outputs; shift the
Iiyama portrait monitor so it's centered on the Acer (not on the whole
AOC+Acer stack). Cleaner coords too: AOC at y=0, Acer at y=1080,
Iiyama at y=600.

Edit `~/.config/niri/config.kdl` to replace the three `output` blocks:

```kdl
output "DP-1" {                       // Acer 1440p 144Hz (primary)
    mode "2560x1440@143.856"
    scale 1
    transform "normal"
    position x=0 y=1080
    variable-refresh-rate
}
output "DP-3" {                       // AOC 1080p 180Hz (above Acer)
    mode "1920x1080@180.003"
    scale 1
    transform "normal"
    position x=320 y=0
    variable-refresh-rate
}
output "DP-2" {                       // Iiyama 1440p portrait (right of Acer)
    mode "2560x1440@69.923"
    scale 1
    transform "90"
    position x=2560 y=600
    variable-refresh-rate
}
```

**Verification:** `niri msg outputs | grep -E 'Current mode|Variable refresh|Logical position|Transform'` — every output reports `Variable refresh rate: supported, enabled`.

---
