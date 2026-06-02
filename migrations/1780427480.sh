echo "Add keyboard-layout pill to the bar (existing shell.json)"
#
# Why: shell.json is user-owned, so a plain `git pull` that ships the
# new keyboard-layout plugin can't add it to an existing user's bar
# layout — the plugin code arrives but is never listed, so it never
# renders. Fresh installs get it for free (nirimaki-config-migrate
# computes the layout from the manifests, which place it after
# system-stats). This migration covers the existing-install gap.
#
# The pill auto-hides whenever only one XKB layout is configured, so
# injecting it is harmless for users who never set up a second layout.
#
# Idempotent: skips if the id is already present anywhere in the bar
# layout, and skips entirely when no shell.json exists yet.

shell_json="$HOME/.config/nirimaki/shell.json"

if [[ ! -f $shell_json ]]; then
  echo "  No shell.json yet — nirimaki-config-migrate will include it. Skipping."
  exit 0
fi

python3 - "$shell_json" <<'PYEOF'
import json, sys, shutil
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as e:
    print(f"  Could not parse {path}: {e} — skipping.", file=sys.stderr)
    sys.exit(0)

NEW_ID = "keyboard-layout"
layout = data.get("bar", {}).get("layout", {})

# Already present anywhere? Nothing to do.
for section in layout.values():
    if isinstance(section, list) and any(
        isinstance(e, dict) and e.get("id") == NEW_ID for e in section
    ):
        print("  keyboard-layout already in the bar layout — nothing to do.")
        sys.exit(0)

right = layout.get("right")
if not isinstance(right, list):
    print("  No bar.layout.right array — skipping.")
    sys.exit(0)

# Place it just before 'audio' to match the manifest's intended slot
# (after system-stats); fall back to right after system-stats, else end.
def index_of(pid):
    for i, e in enumerate(right):
        if isinstance(e, dict) and e.get("id") == pid:
            return i
    return -1

entry = {"id": NEW_ID}
ai = index_of("audio")
si = index_of("system-stats")
if ai >= 0:
    right.insert(ai, entry)
elif si >= 0:
    right.insert(si + 1, entry)
else:
    right.append(entry)

shutil.copy2(path, str(path) + ".bak")
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"  Added keyboard-layout to bar.layout.right (backup: {path.name}.bak).")
print("  Restart Quickshell or run 'quickshell ipc call shell rescanPlugins'.")
PYEOF
