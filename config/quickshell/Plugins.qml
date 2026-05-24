pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Plugin loader.
//
// Discovery: scans two roots for `plugin.json` manifests:
//   ~/.local/share/nirimaki/plugins/builtin/<id>/plugin.json
//   ~/.config/nirimaki/plugins/<id>/plugin.json
// First-party (built-in) ships from the repo and is upgrade-tracked.
// Third-party installs land under user config and survive upgrades.
//
// User overrides live at ~/.config/nirimaki/plugins.json — per-plugin,
// niri-style. Last-wins on the plugin id. Possible values:
//
//   "voxtype": false                                     // disabled
//   "voxtype": { "mount": "bar.left" }                   // moved
//   "voxtype": { "after": "calendar" }                   // reorder
//   "voxtype": { "mount": "bar.left", "before": "..." }  // both
//
// Absent entries fall through to the manifest's declared default.
//
// `requires.binary` in a manifest gates loading on `command -v <bin>`.
// If the binary is missing the plugin stays in the registry (so the
// Settings Menu can show it as "not installed") but doesn't render.
QtObject {
    id: bus

    // All discovered plugins, keyed by id:
    //   { dir, manifest, installed }
    property var registry: ({})

    // Per-plugin user overrides read from plugins.json.
    property var userOverrides: ({})

    // Effective render order, computed per mount:
    //   { "bar.left": [{id, dir, entry, mount, after, before}, ...], ... }
    // Reassigned wholesale on every rebuild so QML bindings refresh.
    property var byMount: ({})

    readonly property string _userPath:
        Quickshell.env("HOME") + "/.config/nirimaki/plugins.json"

    // ---- Public API ----

    // Returns the ordered list of effective plugin entries for a mount.
    // Each entry has: id, dir (absolute), entry (filename, default
    // "main.qml"), mount, after, before. Empty list if mount has no
    // plugins (loader still warming up, or none configured).
    function enabledOrder(mount) { return byMount[mount] || []; }

    // file:// URL for a plugin's entry QML — what Loader.source wants.
    function entryUrl(entry) {
        return "file://" + entry.dir + "/" + (entry.entry || "main.qml");
    }

    // Re-run discovery. Cheap; safe to call after install/uninstall.
    function rescan() { scanProc.running = true; }

    // ---- Discovery: a single bash pipe emits one JSON object per
    // line, each with the plugin's manifest fields plus dir+installed.
    // Per-manifest jq invocation keeps the script readable without
    // needing a separate helper script on disk. ----
    property Process _scanProc: Process {
        id: scanProc
        running: false
        command: ["bash", "-c", `
set -e
shopt -s nullglob
for m in "$HOME"/.local/share/nirimaki/plugins/builtin/*/plugin.json \
         "$HOME"/.config/nirimaki/plugins/*/plugin.json; do
  [[ -e "$m" ]] || continue
  dir=$(dirname "$m")
  bin=$(jq -r '.requires.binary // ""' "$m" 2>/dev/null) || continue
  installed=true
  if [[ -n "$bin" ]]; then
    command -v "$bin" >/dev/null 2>&1 || installed=false
  fi
  jq -c --arg dir "$dir" --argjson installed "$installed" \
       '. + {dir: $dir, installed: $installed}' "$m"
done
`]
        stdout: StdioCollector {
            id: scanOut
            waitForEnd: true
            onStreamFinished: {
                const reg = {};
                const lines = String(scanOut.text || "").split("\n");
                for (const line of lines) {
                    const s = line.trim();
                    if (!s) continue;
                    try {
                        const obj = JSON.parse(s);
                        if (obj.id) {
                            reg[obj.id] = {
                                dir: obj.dir,
                                installed: obj.installed !== false,
                                manifest: obj
                            };
                        }
                    } catch (e) {
                        console.warn("Plugins: bad manifest line:", s, e);
                    }
                }
                bus.registry = reg;
                bus._rebuild();
            }
        }
    }

    // ---- User overrides: watch plugins.json so manual edits propagate
    // without a shell restart. ----
    // The seed ships with a `_comment` documentation block (and may
    // accumulate other underscore-prefixed metadata over time). Strip
    // every `_*` key before treating the rest as override entries.
    property FileView _userFile: FileView {
        path: bus._userPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const raw = JSON.parse(text() || "{}");
                const out = {};
                for (const k in raw)
                    if (!k.startsWith("_")) out[k] = raw[k];
                bus.userOverrides = out;
            } catch (e) {
                console.warn("Plugins: bad plugins.json:", e);
                bus.userOverrides = ({});
            }
            bus._rebuild();
        }
        onLoadFailed: { bus.userOverrides = ({}); bus._rebuild(); }
        onFileChanged: reload()
    }

    // ---- Merge + sort ----
    function _effective(id) {
        const ent = registry[id];
        if (!ent) return null;
        const m = ent.manifest;
        const override = userOverrides[id];
        if (override === false || override === null) return null;
        if (override && typeof override === "object")
            return Object.assign({}, m, override);
        return m;
    }

    function _rebuild() {
        const out = {};
        for (const id of Object.keys(registry)) {
            const eff = _effective(id);
            if (!eff) continue;
            if (!registry[id].installed) continue;
            const mount = eff.mount;
            if (!mount) continue;
            if (!out[mount]) out[mount] = [];
            out[mount].push({
                id: id,
                dir: registry[id].dir,
                entry: eff.entry || "main.qml",
                mount: mount,
                after: eff.after || "",
                before: eff.before || ""
            });
        }
        for (const k of Object.keys(out))
            out[k] = _sortByRefs(out[k]);
        byMount = out;
    }

    // Stable order: scan order is the baseline; an `after: X` moves
    // an item right after X if X is in the same mount, `before: X`
    // places it just before. If the ref is missing the item keeps
    // its scan-order position.
    function _sortByRefs(items) {
        if (items.length < 2) return items;
        const byId = {};
        for (const it of items) byId[it.id] = it;
        let order = items.map(it => it.id);
        for (const it of items) {
            if (it.after && byId[it.after]) {
                order = order.filter(x => x !== it.id);
                const idx = order.indexOf(it.after);
                order.splice(idx + 1, 0, it.id);
            } else if (it.before && byId[it.before]) {
                order = order.filter(x => x !== it.id);
                const idx = order.indexOf(it.before);
                order.splice(idx, 0, it.id);
            }
        }
        return order.map(id => byId[id]);
    }

    // Boot the first scan once. Subsequent scans go through rescan().
    Component.onCompleted: scanProc.running = true
}
