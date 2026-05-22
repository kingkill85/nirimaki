# Install script — next-session handoff

The deferred `install.sh` (blank-Arch → working Nirimaki) is the
next thing to build. Everything it needs to do is **already
specified** in `docs/install-steps.md` (§0–§14, plus §2g/2h/2i,
§11a/11b, §13a, §13b). That file is the source of truth.

> **Spec re-audited 2026-05-22.** Three independent passes against
> the phase docs found ~11 unanimously-missing items (packages,
> mimeapps seed, fontconfig CJK regional rule, mkinitcpio HOOKS
> rewrite + LUKS cmdline swap, UKI splash, bluez/i2c enables).
> All folded into the spec — new sections §2g, §2h, §2i, §11a,
> §11b. Three 2-of-3 items (systemd-networkd enable,
> xdg-desktop-portal-{gnome,gtk}, nautilus) were flagged for human
> review but NOT auto-added; revisit before writing `install.sh`.

This doc just orients the next session — it doesn't re-spec the
work.

---

## Start here

1. Read `docs/install-steps.md` top to bottom. Every package list,
   manual step, and verification check lives there.
2. Read `CLAUDE.md` — repo conventions, what NOT to do, git
   identity inline, Omarchy parity as design lead.
3. Scan the existing `install/` tree:
   - `install/base.packages` — minimal pacman seed list (§2a).
   - `install/bootstrap-extras.sh` — claude-code + pi installers (§2e).
   - `install/login/keyring.sh` — gnome-keyring passwordless setup (§13a).
   - `install/login/sddm.sh` — Nirimaki SDDM theme install (§13b).
4. Skim Omarchy's `install.sh` + `install/` tree at
   <https://github.com/basecamp/omarchy>. Design lead per CLAUDE.md.

---

## What `install.sh` actually is

The thin top-level glue that wires the per-phase install steps
together. Most of the *work* is documented; install.sh's job is
the cross-cutting concerns:

- Clone the repo to `~/.local/share/nirimaki/` (canonical path,
  matches Omarchy's `~/.local/share/omarchy/`).
- One log file at `/var/log/nirimaki-install.log` via `script -qefc`
  — same pattern `bin/nirimaki-update` already uses.
- Single `sudo` prompt at the start; primed for the rest of the run.
- Idempotency — every step must re-run safely (each per-phase
  script already aims for this; install.sh just composes them).
- Reboot-needed detection at the end (kernel landed during install
  — reuse the logic from `bin/nirimaki-update`).

---

## Recommended structure (mirror Omarchy)

```
install.sh                   ← top-level glue
install/
  helpers.sh                 ← sudo prime, pkg-add, log helpers
  preflight.sh               ← Arch + network + user-account checks
  packaging.sh               ← pacman/paru runs from §2a/b/c/d
  bootstrap-extras.sh        ← (exists) claude + pi (§2e)
  config.sh                  ← seed copies + symlinks (§3, §4, §5)
  login/
    keyring.sh               ← (exists)
    sddm.sh                  ← (exists)
  post-install.sh            ← themes, Plymouth, verification (§10–§14)
```

`install.sh` sources each in order. Each piece may need a small
header comment that lists which `install-steps.md` section it
implements — keeps the round-trip back to the spec one click away.

---

## Open decisions for the next session

- **How does the user invoke it?**
  Omarchy ships `curl -fsSL https://omarchy.org/install.sh | bash`
  — the installer itself clones the repo as step 0. Cleaner UX,
  needs a hosted endpoint. Alternative: "clone yourself, then run
  `bash install.sh`" — zero infrastructure, more friction.

- **First-run only, or also "repair"?**
  Cleanest split: `install.sh` for first-run; `nirimaki-update`
  for everything after. Could also make install.sh idempotent so
  `bash install.sh` is safe to re-run for repair. Pick one
  explicitly.

- **AUR bootstrap.**
  `paru` is required for §2d. If absent, install.sh has to
  bootstrap it (`pacman -S --needed base-devel git`, clone
  `aur/paru-bin`, `makepkg -si`). Or require the user to have paru
  installed first — matches Omarchy.

- **Plymouth (§11) is the fragile step.**
  `mkinitcpio` reordering + initramfs rebuild can leave an
  unbootable system if it goes wrong. Run it last so failures
  before it don't compound, and consider gating it behind an
  explicit confirm.

- **`~/.local/share/nirimaki/` already exists on dev boxes**
  (a `default → repo/default` symlink from `dev-link.sh`).
  install.sh must detect that and either bail (preserve dev
  install) or convert it cleanly to an end-user clone. Probably
  bail with a clear error — dev users don't need install.sh.

---

## What NOT to do

- Don't redesign anything documented in `install-steps.md`.
  Update the spec first; treat install.sh as an execution layer.
- Don't write new planning docs alongside this one. If you need
  to expand the design, update the spec.
- Don't break the dev install path. `dev-link.sh` is the dev-side
  flow; install.sh is the end-user flow; they coexist via the
  canonical `~/.local/share/nirimaki/` path test.
- Don't `git config --global` on this machine — pass identity
  inline (see CLAUDE.md → "Git").

---

## Cross-references

| Need | Where |
|---|---|
| The execution spec | `docs/install-steps.md` |
| Per-phase rationale | `docs/phase-*.md` |
| Repo conventions | `CLAUDE.md` |
| Live dev layout | `dev-link.sh` |
| Existing install pieces | `install/` |
| Omarchy reference | <https://github.com/basecamp/omarchy/blob/master/install.sh> |
