echo "Add the 'start' menu button to the far left of the bar (shell.json)"
#
# Why: the new first-party `start` plugin (logo button → settings menu,
# Omarchy custom/omarchy parity) is placed by its manifest mount/before
# on fresh installs. But existing installs own a real ~/.config/nirimaki/
# shell.json whose positional layout never lists `start`, so the loader
# (which only renders listed widgets) would skip it. Inject it at the
# head of bar.left if it isn't already somewhere in the layout.
#
# Idempotent — re-runs are a no-op once `start` is present anywhere.
# Skips quietly if shell.json is absent (fresh install: manifest handles
# placement) or python3 is unavailable (can't safely edit JSON).

SHELL_JSON="$HOME/.config/nirimaki/shell.json"

if [[ ! -f $SHELL_JSON ]]; then
  echo "  skip: no shell.json (manifest mount handles placement)"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 unavailable — add {\"id\":\"start\"} to bar.left by hand"
  exit 0
fi

python3 - "$SHELL_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

layout = cfg.get("bar", {}).get("layout", {})
sections = ("left", "center", "right")

def has_start():
    for s in sections:
        for e in layout.get(s, []):
            if isinstance(e, dict) and e.get("id") == "start":
                return True
    return False

if has_start():
    print("  already present")
    sys.exit(0)

layout.setdefault("left", [])
layout["left"].insert(0, {"id": "start"})
cfg.setdefault("bar", {})["layout"] = layout

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("  inserted {\"id\": \"start\"} at head of bar.left")
PY
