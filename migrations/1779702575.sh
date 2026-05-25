echo "Migrate plugins.json -> shell.json (positional bar layout)"
#
# Why: Group C of the Quickshell-migration plan replaces the
# per-plugin `plugins.json` overrides with a single shell.json that
# owns positional bar layout + inline per-widget settings. New
# plugins (audio panel, network panel, bluetooth panel) require
# settings to live somewhere; shell.json is that place.
#
# What it does:
#   - If ~/.config/nirimaki/shell.json already exists, no-op.
#   - Otherwise reads every plugin manifest from builtin + user dirs,
#     applies the user's plugins.json overrides (if any), resolves
#     after/before refs, writes the positional layout to shell.json,
#     and renames plugins.json to plugins.json.pre-migration.
#
# Idempotent: the script bails immediately when shell.json exists.

"$NIRIMAKI_REPO/bin/nirimaki-config-migrate"
