echo "Plugin system (Phase K): seed plugins.json + ensure plugins/builtin/ link"
#
# Why: Phase K decomposed every bar widget + overlay + bezel + toast
# into plugins under plugins/builtin/. The loader reads two paths —
# ~/.local/share/nirimaki/plugins/builtin/ for first-party and
# ~/.config/nirimaki/plugins/ for third-party — plus a user override
# file at ~/.config/nirimaki/plugins.json. Fresh installs get all
# three set up by install/config.sh, but existing installs only see
# the new files via `git pull` and need this backfill:
#
#   1. Seed ~/.config/nirimaki/plugins.json with the documented stub
#      (if it doesn't exist yet). The file is user-owned thereafter.
#   2. Ensure ~/.local/share/nirimaki/plugins/builtin/ resolves to the
#      shipped tree. On canonical installs (REPO_DIR is already
#      ~/.local/share/nirimaki) this is a no-op — the path resolves
#      directly. On dev installs the symlink dev-link.sh would have
#      created may be missing.

repo_dir="${NIRIMAKI_REPO:-$HOME/.local/share/nirimaki}"

# 1. Seed plugins.json with the documented stub.
cfg="$HOME/.config/nirimaki/plugins.json"
if [[ ! -e $cfg ]]; then
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<'EOF'
{
  "_comment": [
    "User plugin overrides — niri-style last-wins per plugin id.",
    "",
    "Format:  { \"<plugin-id>\": <override>, ... }",
    "Override values:",
    "  false                              — disabled (won't load)",
    "  { \"mount\": \"bar.left\" }            — move to a different mount",
    "  { \"after\": \"calendar\" }            — reorder within current mount",
    "  { \"before\": \"updates\" }            — alternative to `after`",
    "",
    "Missing entry → use the manifest defaults from",
    "  ~/.local/share/nirimaki/plugins/builtin/<id>/plugin.json",
    "",
    "Examples:",
    "  \"voxtype\":  false",
    "  \"weather\":  { \"mount\": \"bar.left\", \"after\": \"active-window\" }",
    "  \"calendar\": { \"after\": \"updates\" }",
    "",
    "Open this file via Settings → Setup → Edit → Plugins, or directly:",
    "  nirimaki edit plugins",
    "",
    "Saves take effect immediately — the loader watches the file."
  ]
}
EOF
  echo "  seeded $cfg"
else
  echo "  kept   $cfg"
fi

# 2. Make sure the loader can find the built-in plugin tree.
canonical="$HOME/.local/share/nirimaki/plugins/builtin"
src="$repo_dir/plugins/builtin"

if [[ -e $canonical ]]; then
  echo "  ok     $canonical (already in place)"
elif [[ -d $src ]]; then
  mkdir -p "$(dirname "$canonical")"
  ln -s "$src" "$canonical"
  echo "  linked $canonical -> $src"
else
  echo "  warn   $src not found — Phase K plugins won't load until repo state is sane" >&2
fi
