# Phase I — Web apps, browser picker, Chromium live theming ✅

Omarchy-parity for the "site-specific browser" pattern: register a
URL as a standalone Chromium window (own app-id, own user-data-dir,
its own icon in the launcher), with the chrome's accent following
the active Nirimaki theme live (no relaunch). Plus a three-browser
baseline (Zen / Firefox / Chromium) with a default-browser picker
in the SettingsMenu.

## Why Chromium specifically

- **`--app=URL`** is the only stable "site-specific browser" mode
  in 2026. Firefox dropped real `--app` years ago. Zen is Firefox-
  based so same constraint.
- **Live theme reload** works via Chrome's managed-policy system:
  write `BrowserThemeColor` to `/etc/chromium/policies/managed/*.json`,
  then `chromium --refresh-platform-policy --no-startup-window` →
  every running instance (browser + webapps) repaints. No equivalent
  exists for Firefox/Zen.
- Mainline Chromium 148+ implements `--refresh-platform-policy` —
  Omarchy's [omarchy-chromium](https://github.com/omacom-io/omarchy-chromium)
  micro-fork was archived 2026-05-07 because upstream caught up.
  Arch's `extra/chromium` works as-is, no fork.

## Webapps stay on Chromium even when default browser is Zen

Decision: `nirimaki-webapp-launch` hardcodes `/usr/bin/chromium`. If the
user picks Firefox or Zen as default browser via the SettingsMenu,
regular link-clicking goes there — but installed webapps still open
in Chromium so live theming keeps working. Same call Omarchy makes.

## What shipped

### bin/nirimaki-theme-set — Chromium hook

After the templates render, parse `~/.config/theme/current/colors.toml`
into an associative array `THEMEC`, then:

```bash
chromium_policy_dir="/etc/chromium/policies/managed"
if [[ -w $chromium_policy_dir ]] && [[ -n ${THEMEC[background]:-} ]]; then
  printf '{"BrowserThemeColor":"%s","BrowserColorScheme":"device"}\n' \
    "${THEMEC[background]}" > "$chromium_policy_dir/nirimaki.json"
  pgrep -x chromium >/dev/null && \
    chromium --refresh-platform-policy --no-startup-window &
fi
```

Key details:
- **`BrowserThemeColor` uses `background`, NOT `accent`.** Omarchy's
  `default/themed/chromium.theme.tpl` is `{{ background_rgb }}` —
  the chrome backdrop matches the desktop, not a tinted accent
  stripe. We had `accent` initially and the chrome looked tinted
  (orange for matte-black, blue for tokyo-night); switched to
  background for Omarchy parity.
- **`BrowserColorScheme=device`** makes Chromium honour the
  freedesktop color-scheme preference (which `gsettings` above
  already flipped per `light.mode`), so light themes get a light
  chrome and vice versa.
- **`-w` guard** silently skips if `/etc/chromium/policies/managed/`
  isn't writable yet — the install step below makes it writable
  once. `nirimaki-theme-set` never sudoes.
- **THEMEC** is parsed once at the top of the reload section; foot's
  OSC palette pass and this chromium pass share it.

### bin/nirimaki-webapp-install — interactive walker

Bash walker mirroring `omarchy-webapp-install` without the gum
dependency. Plain `read` prompts for Name + URL → auto-fetches a
128 px favicon from `https://www.google.com/s2/favicons?domain=…`
(falls back to a manual URL/path prompt if 404). Slugifies the name
to `[a-z0-9-]`, writes:

> **Pass the FULL URL (scheme included) as the `domain` param,
> not the bare host.** Google's service returns 404 for many
> self-hosted subdomains (e.g. `gitlab.nupis.de`) when given a
> bare host, but resolves them when given the full URL. Omarchy
> does this; we initially didn't, and the result was missing
> icons for any site Google's heuristic didn't pre-index by bare
> domain. Fixed 2026-05-22.

```
~/.local/share/applications/nirimaki-webapp-<slug>.desktop
~/.local/share/applications/icons/nirimaki-webapp-<slug>.png
```

The `.desktop`:
```
Exec=$HOME/.local/bin/nirimaki-webapp-launch <slug> '<url>'
StartupWMClass=nirimaki-webapp-<slug>
Categories=Network;WebBrowser;
```

Trailing `read -p "Press Enter to close…"` so the foot window the
walker runs in doesn't disappear before the user can read the
result.

### bin/nirimaki-webapp-launch — chromium --app wrapper

Always uses `/usr/bin/chromium`, regardless of default-browser
setting. Per-app `--user-data-dir`:

```bash
exec chromium \
  --ozone-platform-hint=auto \
  --user-data-dir="$HOME/.cache/nirimaki-webapps/$slug" \
  --class="nirimaki-webapp-$slug" \
  --app="$url" \
  --no-first-run --no-default-browser-check
```

Per-app `--user-data-dir` gives each webapp its own session — the
Omarchy [#1384 RFE](https://github.com/basecamp/omarchy/issues/1384)
asked for this; we made it the default (each webapp gets its own
logins, no cookie cross-contamination). Cost: a few MB per webapp.

### bin/nirimaki-webapp-remove — fzf picker

fzf over `nirimaki-webapp-*.desktop` entries. On confirmation, removes
the `.desktop`, the icon, and the user-data-dir (so logged-in
sessions go too — same UX as Chromium's "remove PWA" UI).

### bin/nirimaki-browser-launch + bin/nirimaki-browser-default

`nirimaki-browser-launch` reads `xdg-settings get default-web-browser`
and exec's the matching binary; bound to `Mod+Shift+B` so the
keybind respects the current default without needing a niri
reload.

`nirimaki-browser-default <chromium|firefox|zen>` calls
`xdg-settings set default-web-browser <name>.desktop` and writes
`set -gx BROWSER <name>` to `~/.config/fish/conf.d/browser.fish`
so new fish shells inherit it.

### config/quickshell/SettingsMenu.qml

Two new top-level branches added (after `setup`, before `system`),
mirroring Omarchy's `omarchy-menu` Install / Remove branches:

```
Install → Web App   (spawns foot running nirimaki-webapp-install)
Remove  → Web App   (spawns foot running nirimaki-webapp-remove)
```

And under `setup`:

```
Default browser → Zen / Firefox / Chromium  (nirimaki-browser-default)
```

i18n keys added to both `en.json` and `de.json`:
`settings.install`, `settings.install.webapp`, `settings.remove`,
`settings.remove.webapp`, `settings.setup.browser*`.

### config/niri/config.kdl

```kdl
window-rule {
    match app-id=r#"^nirimaki-webapp-"#
    opacity 1.0
}
```

Webapps stay fully opaque — translucency degrades text rendering
and the chrome's `BrowserThemeColor` stripe. Matches Omarchy's
`apps/browser.conf` precedent (browsers are always-opaque).

### config/niri/keybinds.kdl

`Mod+Shift+B` switched from hardcoded `spawn "zen-browser"` to
`spawn-sh "$HOME/.local/bin/nirimaki-browser-launch"` — follows the
default-browser setting.

### dev-link.sh

New block links each `config/applications/*.desktop` into
`~/.local/share/applications/` individually (not the dir — user-
installed webapps' .desktops live in the same dir alongside ours).
Currently empty but kept for future repo-owned launcher entries.

## What an install.sh must do for this phase

Add to packages list (Arch core/extra):

```
chromium
firefox
```

(Zen is AUR or external — assume it's already provided.)

Then once, after install:

```bash
# Chromium managed-policy dir — needed for live theme swap.
# Identical to Omarchy install/config/theme.sh.
sudo mkdir -p /etc/chromium/policies/managed
sudo chmod a+rw /etc/chromium/policies/managed

# Initial default browser — pick Zen if available, else Firefox.
xdg-settings set default-web-browser zen-browser.desktop \
  || xdg-settings set default-web-browser firefox.desktop
```

The chmod is the only privileged step at runtime. `nirimaki-theme-set`
never sudoes; if the dir isn't writable it silently degrades to
"no live chromium reload" (newly-spawned chromium instances still
pick up theming on launch via the policy file from a previous run).

Per-user state initialized on first launch:
- `~/.cache/nirimaki-webapps/<slug>/` — created lazily by `nirimaki-webapp-launch`.
- `~/.local/share/applications/icons/` — created lazily by
  `nirimaki-webapp-install`.
- `~/.config/fish/conf.d/browser.fish` — written by
  `nirimaki-browser-default`; remove or pre-seed at install if desired.

## Risks / gotchas

- **`a+rw` on `/etc/chromium/policies/managed/`** is world-writable.
  On a single-user system this is fine; on a shared machine any
  user could set Chrome policies for everyone. Acceptable trade-off
  for the same reason Omarchy ships it that way.
- **Chromium 148+** is the minimum version. Older chromium (Arch
  before late 2025) doesn't implement `--refresh-platform-policy`
  and the live reload silently no-ops. Newly-spawned chromium
  instances still see the policy on startup, so swapping themes
  before launching chromium works on any version.
- **Per-webapp user-data-dir** under `~/.cache/nirimaki-webapps/<slug>/`
  is not in `~/.config/` because Chromium's data dirs aren't
  config — they're caches + cookies + history. `nirimaki-webapp-remove`
  rm -rf's the whole dir on uninstall.
- **No `--app-id=` flag on chromium**: Chromium uses `--class=` and
  it maps to both X11 `WM_CLASS` and Wayland app-id. Verified that
  `niri msg windows --json` reports `app_id: "nirimaki-webapp-<slug>"`
  after spawn (so the window-rule matches).
- **Mod+Shift+B path** uses `spawn-sh "$HOME/.local/bin/nirimaki-browser-launch"`,
  matching the rest of `keybinds.kdl` — no install.sh templating
  required; the shell expands `$HOME` per-user at runtime.

## Sources

- [Omarchy `bin/omarchy-webapp-install`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-webapp-install)
- [Omarchy `bin/omarchy-launch-webapp`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-launch-webapp)
- [Omarchy `bin/omarchy-theme-set-browser`](https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-set-browser)
- [Omarchy `install/config/theme.sh`](https://github.com/basecamp/omarchy/blob/dev/install/config/theme.sh) — the one-time chmod
- [Omarchy `default/themed/chromium.theme.tpl`](https://github.com/basecamp/omarchy/blob/dev/default/themed/chromium.theme.tpl) — confirms BG, not accent
- [omacom-io/omarchy-chromium](https://github.com/omacom-io/omarchy-chromium) — archived 2026-05-07
- [Dynamic Chrome Themes — Helmut Januschka](https://www.januschka.com/chromium-omarchy.html)
