# Phase H — Terminal (fish + tools)

Make the terminal the stand-out daily-driver experience. Fish as the
interactive shell, bash kept untouched for script + system
compatibility, starship across both so the prompt is identical
regardless of which you're in. Plus a curated modern-CLI toolkit and
the theme system extended to skin all of it.

## Shell stack decision

- **fish** — interactive login shell for the user. `chsh -s /usr/bin/fish`.
- **bash** — stays as `/bin/sh` semantics, `#!/bin/bash` shebangs, and
  every system / package script. Untouched.
- **starship** — single prompt config, sourced in both shells. A bash
  session and a fish session show the same prompt.

This works because `chsh` only changes the user's interactive login
shell. `/bin/sh`, `bash script.sh`, and every shebanged script are
unaffected.

## Tool list (locked)

### Core 8 — the floor

| Tool | Replaces | Key wiring |
|---|---|---|
| **starship** | bash PS1 / fish prompt | `~/.config/starship.toml`, themed per Nirimaki palette |
| **eza** | ls | abbr `ls`, `ll`, `lt` (tree) |
| **bat** | cat, less for help | `$PAGER=bat`, themed |
| **fzf** | nothing — adds fuzzy everywhere | Ctrl-R/T, Alt-C |
| **zoxide** | cd | `z foo` jump, `zi` interactive |
| **ripgrep** | grep | `rg` |
| **fd** | find | `fd` |
| **git-delta** | git diff | `[core] pager = delta` in `~/.gitconfig` |

### Tier 2 — daily wins

`lazygit · tealdeer (tldr) · pay-respects · sd · ouch · dust · duf ·
procs · xh`

### Light extras

`hyperfine · tokei`

### Multiplexer

`tmux` — included on user request despite niri columns covering most
of the same ground. Baseline config + tpm in H7.

### Fish plugins (via fisher)

`fisher · fzf.fish · autopair.fish · puffer.fish · done · sponge`

`done` is the cool one: long-running commands trigger a desktop
notification when they finish — hooks straight into our
NotificationService.

### Homegrown

- `bookmark` — fish function + fzf-picker for named directory pins
  (the "T-marks" layer above zoxide's frecency).
- `nirimaki-quake-toggle` — drop-down kitty toggle bound to `Mod+grave`.

### Explicitly out of scope

- **trash-cli** — user vetoed during brainstorm. Plain `rm` stays.
- **atuin** — deferred; fzf+fish history is enough.
- **autojump / fasd / z.fish / broot / navi / mcfly / dog / gping /
  k9s / mosh / zellij** — covered by other picks or not needed.

## Step targets

| Step | Topic | What changes |
|------|-------|--------------|
| **H1** | fish + chsh + scaffolding | Install fish, add to `/etc/shells`, `chsh -s /usr/bin/fish`. Repo-side `config/fish/` skeleton. `dev-link.sh` linked. |
| **H2** | starship | Install, template `starship.toml` per theme, source in `config.fish` + `~/.bashrc`, hot-reload on `nirimaki-theme-set`. |
| **H3** | Core tools | eza · bat · fzf · zoxide · ripgrep · fd · git-delta — install, abbrs, fish key bindings, `$PAGER`/`$EDITOR` env. |
| **H4** | Tier 2 + light | lazygit · tealdeer · pay-respects · sd · ouch · dust · duf · procs · xh · hyperfine · tokei. |
| **H5** | Fish plugins | fisher bootstrap, install fzf.fish/autopair/puffer/done/sponge. Verify `done` toasts via NotificationService. |
| **H6** | Homegrown | `bookmark` fish function + Quickshell-style fzf picker. `nirimaki-quake-toggle` script + niri rule. |
| **H7** | tmux | Baseline `tmux.conf` (prefix, vi-mode, mouse, true-color, sane copy). Themed via template in H9. Decide tpm vs hand-rolled when we land it. |
| **H8** | Keybind sweep | `fish_user_key_bindings` (Ctrl-R/T, Alt-C, Ctrl-B, Ctrl-G, Alt-E, Ctrl-X Ctrl-L). Mirror via `~/.inputrc` for bash. niri adds: `Mod+grave` quake, `Mod+Shift+Return` floating term, `Mod+Alt+G` floating lazygit. |
| **H9** | Theme integration | Templates: `starship.toml.tpl`, `bat-theme` selection, `delta.gitconfig.tpl`, `fish-colors.fish.tpl`, `lazygit.yml.tpl`, `tmux-theme.conf.tpl`. Sourced/applied by `nirimaki-theme-set`. |

## Locked decisions

1. **fish via chsh, not via kitty-only.** Means SSH sessions, TTY,
   and any new terminal land in fish — consistent. The kitty
   `shell` setting is left at default (uses login shell).
2. **All repo scripts stay bash.** `bin/nirimaki-*` and `install.sh`
   never converted. `#!/bin/bash` shebangs. Rationale:
   compatibility with non-Nirimaki users running them; fish is for
   the user's interactive sessions only.
3. **starship in both shells.** Means a `bash` invocation from
   within fish shows the same prompt. Single
   `~/.config/starship.toml`, themed per Nirimaki theme.
4. **Abbreviations > aliases in fish.** Per fish idiom — expand
   visibly on space so the user always knows what's running.
   Bash gets equivalent aliases in `~/.bashrc` for the compat
   path. Suggested set lives in `config/fish/conf.d/abbreviations.fish`.
5. **`done` plugin wires into NotificationService.** Threshold is
   the plugin's default (10s); reuses libnotify which our daemon
   already speaks.
6. **Quake terminal = single floating kitty instance.** Fixed
   `app-id=nirimaki-quake-term`, niri window-rule for float + size +
   centre, `nirimaki-quake-toggle` script handles show/hide via niri IPC
   (spawn first time, focus-toggle thereafter).
7. **No multiplexer keybind conflicts.** tmux's prefix stays
   `Ctrl-B` (default) — niri's `Mod` is super, no overlap.
8. **Theme reload for shell prompt.** `nirimaki-theme-set` already does
   IPC reloads for Quickshell + signals kitty. Add a starship
   refresh by re-rendering `starship.toml` from the template; the
   running shell picks up the new file on next prompt redraw
   (starship reads the file each render).

## Risks

- `chsh` requires the user's password. Cannot be done from this
  agent; document the command for the user to run.
- Forgetting `/etc/shells` will make `chsh` reject `/usr/bin/fish`.
  H1 explicitly checks + edits with sudo.
- Bash compatibility regressions: anything in `.bashrc` that
  assumed bash-only env vars (e.g. `PROMPT_COMMAND`) must be
  preserved when we touch `.bashrc`. Read first, append only.
- `done` plugin sends notifications for *every* foregrounded
  command past the threshold — could become noisy. Default
  threshold is 10s; tune via `set -g __done_min_cmd_duration`.
- Theme hot-reload for fish: changing
  `~/.config/fish/conf.d/fish-colors.fish` only takes effect for
  *new* fish sessions unless we `source` it via an IPC. `nirimaki-theme-set`
  will need to write a fish universal variable
  (`fish -c 'set -U fish_color_...'`) — universal variables persist
  AND propagate to all running fish instances. This is the clean
  story.
- Quake terminal toggle race: spawning the kitty instance is
  async; the toggle script must handle "not running yet" by
  spawning and waiting for the window to appear via `niri msg
  windows --json` poll.

## Recommended order

H1 → H2 → H3 → H5 → H4 → H6 → H7 → H8 → H9

i.e. shell up first, prompt second, core tools and the
plugin-manager-driven niceties (which the keybinds depend on)
together, then the longer-tail tools, then homegrown stuff, tmux,
keybind sweep, and finally theme integration as a polish pass.

## Sources

- [fish-shell docs](https://fishshell.com/docs/current/)
- [starship config](https://starship.rs/config/)
- [fisher](https://github.com/jorgebucaran/fisher)
- [done.fish](https://github.com/franciscolourenco/done)
- [Omarchy terminal defaults](https://github.com/basecamp/omarchy)
  — for parity reference on env vars + aliases.
- [omarchy-nvim](https://github.com/nicomiguelino/omarchy-nvim) —
  the actual nvim config Omarchy ships; ported in spirit to
  Nirimaki's `config/nvim/`.

---

## Outcome

Everything from H1–H9 plus a parity-driven LazyVim pass landed:

- ✅ **H1** — fish chsh'd as login shell. `config/fish/{config.fish,
  conf.d/{abbreviations,greeting,tools}.fish}` linked via dev-link.
  bash stays as `/bin/sh` interpreter and as fallback login shell.
- ✅ **H2** — starship installed, `starship.toml.tpl` rendered per
  Nirimaki theme into `~/.config/starship.toml`. Sourced in both
  shells so a `bash` drop-in from fish shows the same prompt.
- ✅ **H3** — eza · bat · fzf · zoxide · ripgrep · fd · git-delta.
  `cd` replaced by `zoxide --cmd cd` (literal-first, frecency
  fallback). bat is the help / man pager. delta is git's pager.
- ✅ **H4** — lazygit · tealdeer · pay-respects (`pay-respects-bin`
  from AUR) · sd · ouch · dust · duf · procs · xh · hyperfine ·
  tokei. `f` corrects the previous failed command.
- ✅ **H5** — fisher + fzf.fish + autopair.fish + puffer-fish + done
  + sponge. `done` is wired into the NotificationService → toast
  on commands taking >5s.
- ✅ **H6** — `bm` fish function (named directory bookmarks,
  `~/.local/share/fish/bookmarks` store, Ctrl-B fzf picker).
  `nirimaki-quake-toggle` script for the Quake-style drop-down terminal,
  bound to `Mod+grave`. Persists via a `tmux new-session -A -s
  quake` wrapper so closing the terminal keeps the session alive.
  (Originally targeted kitty; rewritten to foot on 2026-05-21 —
  see the post-Phase-H section below.)
- ✅ **H7** — tmux 3.6a + the Omarchy `tmux.conf` ported verbatim
  (C-Space prefix, Alt+1-9 windows, Alt+Enter pane splits, vi
  copy, status bar). Plus the four bash-fns ported as fish
  functions: `tdl` / `tds` / `tdlm` / `tsl`.
- ✅ **H8** — keybind sweep. Lock moved off `Ctrl+Alt+L` →
  `Mod+Shift+L` so the terminal can use Ctrl-Alt-L for fzf.fish's
  git-log picker. `Mod+grave` toggles the quake terminal. Floating
  lazygit (`Mod+Alt+G`) and floating scratch terminal
  (`Mod+Shift+Return`) were trialled and removed — quake covers
  the use case, and lazygit only makes sense inside a git repo.
- ✅ **H9** — theme integration across the toolkit. Per-theme
  templates: `starship.toml.tpl`, `fish-colors.fish.tpl`,
  `bat-theme.tmTheme.tpl`, `lazygit.yml.tpl`, `yazi-theme.toml.tpl`.
  delta and tmux use ANSI-named colours which already follow the
  kitty palette → no per-theme template needed.

### LazyVim integration (bonus, out of original H9 scope)

Modelled after `basecamp/omarchy` + `nicomiguelino/omarchy-nvim`:

- `config/nvim/` — LazyVim/starter as the base, linked via
  dev-link, with five Nirimaki additions in `lua/plugins/`:
  - `all-themes.lua` — every theme plugin registered with
    `lazy = true, priority = 1000` so swaps don't trigger a
    plugin install.
  - `theme.lua` — proxy that `dofile()`s
    `~/.config/theme/current/neovim.lua` (the active theme's
    spec), portable across machines without symlinks.
  - `nirimaki-theme-hotreload.lua` — defines
    `_G.NirimakiReloadTheme()` invoked from `nirimaki-theme-set` via
    `nvim --remote-expr` against `$XDG_RUNTIME_DIR/nvim.*.0`
    sockets. Re-dofile's the theme, clears highlights, unloads
    the previous plugin's lua modules, loads the new
    colorscheme plugin via `lazy.core.loader.colorscheme`,
    applies it, re-sources transparency.lua.
  - `disable-news-alert.lua` + `snacks-animated-scrolling-off.lua`
    — Omarchy parity.
- `plugin/after/transparency.lua` — strips `bg` from every
  significant highlight group so nvim panes are see-through onto
  kitty's translucency.
- `lazyvim.json` — `editor.neo-tree` extra enabled.
- `EDITOR=nvim` set in fish.

Hot-swap propagates live for 20 of 22 themes; `ristretto` and
`last-horizon` apply the basic monokai-pro / aether scheme but
their custom filter / palette overrides require an nvim restart
to take effect (their per-theme `neovim.lua` uses
`config = function() ... end` instead of `opts = {}`).

### kitty.conf into the repo (drift from D-phase decision)

`~/.config/kitty/kitty.conf` was previously per-machine. Folded
into `config/kitty/kitty.conf` and linked via dev-link, with
Omarchy-parity additions: explicit `JetBrainsMono Nerd Font`,
`window_padding_width 14`, `allow_remote_control yes`, powerline
tab bar, block cursor, no audio bell. Font size left at kitty's
default 11pt — Omarchy's 9pt is too small at 1440p+.

> **Superseded 2026-05-21** by the foot migration below.
> `config/kitty/` and `config/theme/templates/kitty.conf.tpl` are
> gone from the repo; the kitty package can stay installed as a
> fallback but is no longer first-class.

### Omarchy shortcut ports (fish functions)

| Function | Equivalent of | Purpose |
|---|---|---|
| `t`   | `alias t='tmux attach \|\| tmux new -s Work'` | Drop into the persistent Work session |
| `n`   | `n() { ... nvim . ; ... nvim "$@"; }` | nvim with cwd if no args |
| `ff`  | `alias ff='fzf --preview ...'`         | fzf with bat / kitty-icat preview |
| `eff` | `alias eff='$EDITOR $(ff)'`            | Pick file with ff → open in nvim |
| `oc`  | `alias c='opencode'` (renamed)         | opencode CLI (`c` reserved for `clear`) |
| `cc`  | `alias cx='claude --permission-mode bypassPermissions'` (renamed) | Claude Code (shadows /usr/bin/cc) |
| `io`  | `alias ic='tdl c'`                     | IDE layout + opencode |
| `ic`  | `alias ix='tdl cx'`                    | IDE layout + claude |
| `ioc` | `alias icx='tdl c cx'`                 | IDE layout + both AIs |

### Side fixes that landed during Phase H

- **Quickshell Launcher.qml** — `runInTerminal` desktop entries
  (nvim, htop, btop, bluetui …) were launching with no TTY and
  exiting immediately. Now wrapped in `kitty -e`.
- **KeybindSheet i18n** — sections + bind labels now go through
  `I18n.t("keybind.section.<slug>")` / `keybind.title.<slug>` with
  fallback to the original. German translations added for all 19
  sections + 31 bind titles in `de.json`.
- **KeybindSheet keyboard scroll** — Up / Down / PageUp / PageDown
  / Home / End now scroll the list; typing still goes to the
  filter.
- **KeybindSheet structure refactor** — Column nested inside
  `keyCatcher` (was a sibling) so focus chain is clean.
- **DialogShell.qml** — the click-blocking MouseArea was dropped
  (the scrim and dialog are separate WlrLayershell surfaces —
  Wayland delivers clicks to one or the other, not both).

### KeybindSheet — keyboard nav redone the stock way

The hand-rolled `keyCatcher` Item + custom `WheelHandler` + direct
`ListView.contentY` math is gone. Replaced with the same pattern
Launcher uses:

- Filter is a real `TextInput` with `focus: true` — typing and
  backspace are native, no `event.text` synthesis.
- `Keys.onDownPressed` / `Keys.onUpPressed` call a `move(delta)`
  helper that sets `list.currentIndex` and `positionViewAtIndex(idx,
  ListView.Contain)`. `Keys.onPressed` covers PgUp/PgDn (Qt's
  `Keys` attached property has no named signal for those).
- Bind-row delegate now responds to `ListView.isCurrentItem` with a
  faint `fg @ 7% alpha` background + accent-colored chord text, so
  Up/Down actually *show* something happening. Without that
  highlight the previous code was scrolling an invisible cursor —
  events were arriving (confirmed via `console.log`), the user just
  couldn't tell.

Direct `contentY` manipulation was the cause of the earlier "won't
scroll to the end / visual glitches on scroll-up" bug: ListView is
virtualising with non-uniform delegate heights (section=30,
bind=26), so `contentHeight` is only an estimate until all
delegates realise — assigning `contentY = contentHeight - height`
lands past the real end and snaps + glitches as more delegates
realise. `positionViewAtIndex` doesn't have this problem because
Qt handles realisation internally.

### Post-Phase H: foot replaced kitty (2026-05-21)

Default terminal swap to [foot](https://codeberg.org/dnkl/foot) —
1.27 from the Arch package. Reasoning the user gave: lighter, native
Wayland (no XWayland fallback path), better fit with niri's column
model. Migration was full, not surface-level:

- **`Mod+Return`** → `spawn "foot"` (was kitty).
- **`config/foot/foot.ini`** — repo-side base config. Same shell /
  font / padding intent as the old kitty.conf, plus an explicit
  `[key-bindings]` rebinding `clipboard-paste` onto Shift+Insert so
  the universal-clipboard wtype injection (Mod+V) actually pastes
  CLIPBOARD instead of foot's default `primary-paste-selection`.
- **`config/theme/templates/foot.ini.tpl`** — palette + alpha=0.99,
  rendered into both `[colors-dark]` and `[colors-light]` (foot
  1.27 deprecated the unified `[colors]` section) and included
  into foot.ini at the top level. New foot instances pick this up
  on launch.
- **Live theme reload** doesn't use SIGUSR1 like kitty did — foot's
  SIGUSR1 only toggles the in-memory `[colors-dark]`/`[colors-light]`
  pair that was loaded at startup, it doesn't re-read the file.
  nirimaki-theme-set instead writes OSC palette sequences (OSC 4 for
  indexed 0–15, OSC 10/11/12/17/19 for fg/bg/cursor/selection)
  directly to each running foot's pts slave (found via
  `/proc/<child-shell-pid>/fd/1`). Foot interprets the OSCs the
  same as if a program inside the terminal printed them, so live
  recolouring works regardless of what's on the command line —
  vim, less, fzf, lazygit all repaint immediately.
- **`nirimaki-quake-toggle`** — switched to `foot --app-id=nirimaki-quake-term`
  (was `kitty --class=...`). tmux wrapper unchanged: foot takes the
  exec command as positional args after options, no `-e` flag like
  kitty.
- **`NiriService.launchTui` + `SettingsMenu` TUI spawns** —
  `kitty --class=tui-X -e CMD` rewritten as
  `foot --app-id=tui-X CMD`. `--override initial_window_*` (kitty
  syntax) replaced with foot's `--window-size-chars=120x32`.
- **`Launcher.qml`** — `runInTerminal` wrap is now
  `["foot", ...e.command]`.
- **`ff.fish`** — image preview path forks on `$TERM`: foot* uses
  `img2sixel` (foot has native sixel rendering); xterm-kitty keeps
  kitty icat as a fallback in case kitty is launched manually.
- **niri window-rules** in config.kdl already matched on `app-id`
  (which foot sets via `--app-id=` exactly the way kitty set it via
  `--class=`); only the explanatory comments needed updating.
  Floating TUI rule (`^tui-`) and quake rule (`nirimaki-quake-term`) both
  apply identically to foot.
- **i18n** — `keybind.title.terminal-kitty` →
  `keybind.title.terminal-foot` (the slug is derived from the
  `hotkey-overlay-title`, which itself changed).
- **Removed**: `config/kitty/`, `config/theme/templates/kitty.conf.tpl`,
  the kitty `link_path` line in `dev-link.sh`. `config/foot/` linked
  instead. The kitty pacman package is left in place — kitty still
  works if launched manually, it's just no longer wired through the
  shell.

> No keybind conflicts. Mod+Insert / Shift+Insert paths are
> identical between the two terminals; foot's `[key-bindings]`
> entries above ensure parity.

### Still broken — mouse-wheel in KeybindSheet

Even after removing the custom WheelHandler and falling back to
ListView's native Flickable wheel handling, the mouse wheel does
not scroll the keybind sheet. Other Quickshell projects on
WlrLayershell report native wheel works for them, so this is most
likely environmental — note the runtime warning:

> Quickshell was built against Qt 6.11.0 but the system has
> updated to Qt 6.11.1 without rebuilding the package.

Worth rebuilding `quickshell` (`yay -S quickshell-git` or rebuild
the AUR package) before treating this as a Quickshell/niri bug.
Keyboard nav is the daily-driver path either way.

### Out-of-Phase-H groundwork picked up while doing it

- **Bash compat layer** — `~/.bashrc` (still per-machine, NOT
  symlinked) sources starship, zoxide, fzf bindings, pay-respects,
  BAT_THEME/PAGER/MANPAGER. So an interactive `bash` from inside
  fish gets the same prompt + most of the same tools.
- **delta in `~/.gitconfig`** — `[core] pager = delta`,
  side-by-side, line-numbers, navigate, `syntax-theme = ansi`
  (auto-follows kitty palette).

