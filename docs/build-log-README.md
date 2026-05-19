# Nirimaki setup log

A reproducible log of every change made to a barebones Arch + niri install,
intended to be turned into a shell script later.

**Nirimaki** = `niri` + `maki` (rolled sushi) — a sister name to
Omarchy (`omakase` + `arch`). The project takes heavy inspiration
from `basecamp/omarchy` but is built on niri + Quickshell rather
than Hyprland + Waybar. Branding identity (wordmark, boot splash,
plymouth visuals) is documented in
[phase-d-theming.md § Step D9](phase-d-theming.md#step-d9--branding-identity-nirimaki-logo-uki-splash-plymouth-visuals).

**Assumed starting state**

- Arch Linux
- niri installed with stock `~/.config/niri/config.kdl`
- kitty installed
- pipewire + wireplumber installed
- No waybar / fuzzel / mako / swaylock / screenshot tools yet
- Three monitors connected via DisplayPort

---

## Layout of this directory

| File | Phase | Scope |
|------|-------|-------|
| [phase-a-foundations.md](phase-a-foundations.md) | A — Foundations | Steps 1–7. Multi-monitor outputs, core CLI tools (paru, playerctl, brightnessctl), default browser, fonts (Noto + regional CJK), kitty config, VRR refinement. |
| [phase-b-shell.md](phase-b-shell.md)             | B — Shell | Steps 8–25. Quickshell stand-up: bar scaffold, every bar widget (Workspaces, ActiveWindow, Audio, Tray, Calendar, SystemStats, Media, Bluetooth, Network), launcher, notifications, wallpaper, idle lock, screenshot, auto-start. |
| [phase-c-polish.md](phase-c-polish.md)           | C — Polish | Steps 26–38. Zen window-rule fix, OSD bezel, clipboard picker, power menu, update widget, weather flyout, tray fixes, emoji picker, screen recording, voxtype dictation, calendar/locale polish, external brightness via ddcutil, per-output workspaces (reverted), post-Phase-C UX refinements. |
| [phase-d-theming.md](phase-d-theming.md)         | D — Theming | Visual consistency pass: theme directory under `~/.config/theme/`, swappable color tokens, kitty/btop templates, Quickshell-native lock screen, GTK + cursor + icon themes (Yaru variants), Qt5/6 via qt5ct/qt6ct, share picker, Plymouth bootsplash (blank + centred password). **D9 — Nirimaki branding pass:** ASCII wordmark via patorjk.com, custom `ascii2png.sh` block-pixel renderer, 10 colour variants, amber as canonical accent, UKI `.splash` swap (replaces upstream Arch logo with our BMP), Plymouth logo + fake/real progress bar ported from Omarchy. |
| [phase-e-consistency.md](phase-e-consistency.md) | E — Consistency | Post-MVP cleanup, aligned to Omarchy's look: imported all Omarchy themes (sans omarchy-branded backgrounds), niri 2 px square-corner borders matching Hyprland's, Quickshell visual reset (square corners, translucent cards, font sweep, JetBrainsMono Nerd Font), single-popup bus, niri blur + window translucency, theme picker (Mod+Shift+T), background picker (Mod+Shift+B). |
| [phase-f-i18n-keybinds.md](phase-f-i18n-keybinds.md) | F — i18n + keybinds | Translation dictionary singleton + JSON files for `en`/`de`, sweep of hardcoded QML strings, consolidation of niri keybinds into an included `keybinds.kdl`, Quickshell keybind-sheet overlay (Mod+F1), Omarchy-primary keybind conventions, universal `Mod+C`/`V`/`X` clipboard, lock-screen i18n + wallpaper backdrop. |
| [phase-g-settings.md](phase-g-settings.md) | G — Settings dialogs | Unified Omarchy-style settings menu in Quickshell (Mod+Alt+Space), hierarchical Style / Setup / System drilldown with breadcrumb. Setup launches the same TUIs Omarchy ships (wiremix / bluetui / impala) in floating kitty windows. Language picker writes `~/.config/quickshell/locale` to override `$LANG`; Calendar re-tints month/weekday names live on language switch. Appendix: full transparency/blur rework — per-window-state opacity (0.97/0.9 Omarchy parity), non-xray blur on windows + Quickshell layer-shell namespaces, global `draw-border-with-background false` (niri#1823), AMD opacity workaround (niri#2346) via `background_opacity 0.99`. |

---

## Conventions used throughout

- Each step has a numbered `## Step N — Title`, a **Goal** statement,
  the exact commands / files that change, a **Verification** block, and
  any **Gotchas** discovered while doing it.
- "Step Nb" appears when a follow-up fix amends an earlier step
  without renumbering (e.g. Step 30b refines the Updates widget from
  Step 30).
- All paths are written explicitly — no `~` shortcuts in shell snippets
  that get pasted into scripts.
- `[[double-bracket-links]]` reference auto-memory entries (in this
  user's `~/.claude/projects/-home-michael/memory/`) that capture
  workflow rules learned while building this.
