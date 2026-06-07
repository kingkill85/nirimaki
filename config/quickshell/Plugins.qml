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
//
// ---- Manifest schema v2 (Group B) ----
// The legacy schema uses `mount` (single string) + `entry` (single
// filename). The v2 schema adds:
//   - `kinds: ["bar-widget" | "overlay" | "panel" | "menu" | "bezel" | "toast" | "service"]`
//   - `entryPoints: { <kind>: <filename> }`
// Backward compat: if `kinds` is absent we infer one from `mount`;
// if `entryPoints` is absent we synthesize it from `entry`.
//
// ---- Lifecycles ----
// `bar-widget` / `bezel` / `toast` are eager — loaded into the bar host
// or as top-level Variants under ShellRoot.
// `overlay` / `panel` / `menu` are lazy — instantiated only when
// `summon(id)` is called (typically via the shell IPC handler).
// `service` is eager but headless (singleton-style; no entry surface).
QtObject {
    id: bus

    // All discovered plugins, keyed by id:
    //   { dir, manifest, installed, kinds: [...], entryPoints: {kind: filename} }
    property var registry: ({})

    // Per-plugin user overrides read from plugins.json.
    property var userOverrides: ({})

    // Effective render order, computed per mount:
    //   { "bar.left": [{id, dir, entry, mount, after, before}, ...], ... }
    // Reassigned wholesale on every rebuild so QML bindings refresh.
    property var byMount: ({})

    // Same shape but keyed by kind — populated for v2-style plugins:
    //   { "overlay": [{id, dir, kinds, ...}, ...], "panel": [...], ... }
    property var byKind: ({})

    // Lazy-summon state for kind:overlay/panel/menu plugins.
    //   { "dev-gallery": true, "audio": false, ... }
    // shell.qml's overlay/panel/menu Loaders gate `active` on this.
    property var summoned: ({})

    // Optional payload passed to the most recent summon for an id.
    //   summon("audio", {tab: "mixer"})  →  summonPayload.audio === {tab: "mixer"}
    // Plugins that care read this at instantiation time; reset on hide.
    property var summonPayload: ({})

    // Top-bar visibility (Omarchy's Mod+Shift+Space waybar toggle parity).
    // Runtime-only state — every per-screen Bar binds its `visible` to
    // this, so flipping it hides/shows all bars at once and the
    // PanelWindow drops its exclusive zone so windows reflow to fill.
    // Not persisted: resets to visible on shell restart, matching
    // waybar's SIGUSR1 toggle.
    property bool barVisible: true

    readonly property string _userPath:
        Quickshell.env("HOME") + "/.config/nirimaki/plugins.json"

    // ---- Public API ----

    // Returns the ordered list of effective plugin entries for a mount.
    // Each entry has: id, dir (absolute), entry (filename, default
    // "main.qml"), mount, after, before. Empty list if mount has no
    // plugins (loader still warming up, or none configured).
    function enabledOrder(mount) { return byMount[mount] || []; }

    // file:// URL for a plugin's entry QML — what Loader.source wants.
    // Accepts either a byMount/byKind entry object (legacy) or a plain
    // {dir, entry} pair.
    function entryUrl(entry) {
        return "file://" + entry.dir + "/" + (entry.entry || "main.qml");
    }

    // Resolve a plugin's entry file for a specific kind (v2). Falls
    // back to legacy `entry` field when entryPoints[kind] is missing.
    //   entryUrlFor("audio", "panel")  →  "file:///.../audio/Panel.qml"
    function entryUrlFor(id, kind) {
        const ent = registry[id];
        if (!ent) return "";
        const filename = (ent.entryPoints && ent.entryPoints[kind])
                      || ent.manifest.entry
                      || "main.qml";
        return "file://" + ent.dir + "/" + filename;
    }

    // ---- Lazy-summon API (v2 kinds: overlay / panel / menu) ----

    function isSummoned(id) { return summoned[id] === true; }

    function summon(id, payload) {
        if (!registry[id]) {
            console.warn("Plugins.summon: unknown plugin", id);
            return false;
        }
        const next = Object.assign({}, summoned);
        next[id] = true;
        summoned = next;
        if (payload !== undefined) {
            const pp = Object.assign({}, summonPayload);
            pp[id] = payload;
            summonPayload = pp;
        }
        return true;
    }

    function hide(id) {
        if (!summoned[id]) return;
        const next = Object.assign({}, summoned);
        delete next[id];
        summoned = next;
        if (summonPayload[id] !== undefined) {
            const pp = Object.assign({}, summonPayload);
            delete pp[id];
            summonPayload = pp;
        }
    }

    function toggle(id, payload) {
        if (summoned[id]) hide(id);
        else              summon(id, payload);
    }

    // Per-plugin setting lookup. Reads inline settings on the shell.json
    // bar-layout entry; falls back to `fallback` if the plugin isn't in
    // any bar section or the key is absent.
    function settingFor(id, key, fallback) {
        return Config.settingFor(id, key, fallback);
    }

    // JSON-friendly snapshot for `quickshell ipc call shell listPlugins`.
    function listPlugins() {
        const out = [];
        for (const id of Object.keys(registry)) {
            const ent = registry[id];
            const m = ent.manifest;
            out.push({
                id: id,
                name: m.name || id,
                kinds: ent.kinds,
                mount: m.mount || "",
                installed: ent.installed,
                summoned: isSummoned(id)
            });
        }
        return out;
    }

    // Re-run discovery. Cheap; safe to call after install/uninstall.
    function rescan() { scanProc.running = true; }

    // ---- Internal: schema-v2 normalisation ----

    // Infer kinds from a v1 manifest's `mount` field. Bar mounts all
    // become "bar-widget"; overlay/bezel/toast become themselves.
    function _kindsFromMount(mount) {
        if (!mount) return [];
        if (mount === "bar.left" || mount === "bar.center" || mount === "bar.right")
            return ["bar-widget"];
        if (mount === "overlay") return ["overlay"];
        if (mount === "bezel")   return ["bezel"];
        if (mount === "toast")   return ["toast"];
        return [mount];
    }

    function _normalizeManifest(m) {
        const kindsExplicit = Array.isArray(m.kinds) && m.kinds.length > 0;
        const kinds = kindsExplicit ? m.kinds.slice()
                                    : _kindsFromMount(m.mount);
        const entryPoints = (m.entryPoints && typeof m.entryPoints === "object")
                          ? Object.assign({}, m.entryPoints)
                          : {};
        // If entryPoints is empty, synthesize one entry per kind from
        // the legacy `entry` field (default main.qml).
        if (Object.keys(entryPoints).length === 0) {
            const file = m.entry || "main.qml";
            for (const k of kinds) entryPoints[k] = file;
        }
        return { kinds: kinds, entryPoints: entryPoints, v2: kindsExplicit };
    }

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
                            const norm = bus._normalizeManifest(obj);
                            reg[obj.id] = {
                                dir: obj.dir,
                                installed: obj.installed !== false,
                                manifest: obj,
                                kinds: norm.kinds,
                                entryPoints: norm.entryPoints,
                                v2: norm.v2
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
        const outMount = {};
        const outKind  = {};
        const barMounts = { "bar.left": 1, "bar.center": 1, "bar.right": 1 };

        // ---- Bar layout ----
        // Prefer shell.json (positional, with inline settings) when valid;
        // otherwise fall back to the legacy manifest+plugins.json path
        // (after/before resolution). Either way only the three bar.*
        // mounts come from this branch.
        if (Config.valid) {
            const sections = [
                ["bar.left",   Config.barLeft],
                ["bar.center", Config.barCenter],
                ["bar.right",  Config.barRight]
            ];
            for (const [mount, entries] of sections) {
                outMount[mount] = [];
                for (const e of entries) {
                    const id = e && e.id;
                    if (!id) continue;
                    const ent = registry[id];
                    if (!ent || !ent.installed) continue;
                    // Strip the id so the rest of the entry IS the settings.
                    const settings = {};
                    for (const k of Object.keys(e))
                        if (k !== "id") settings[k] = e[k];
                    outMount[mount].push({
                        id: id,
                        dir: ent.dir,
                        entry: ent.entryPoints["bar-widget"]
                            || ent.manifest.entry
                            || "main.qml",
                        mount: mount,
                        settings: settings
                    });
                }
            }
        } else {
            // Legacy fallback for bar mounts (fresh install pre-migration).
            for (const id of Object.keys(registry)) {
                const eff = _effective(id);
                if (!eff) continue;
                const ent = registry[id];
                if (!ent.installed) continue;
                const mount = eff.mount;
                if (!mount || !barMounts[mount]) continue;
                if (!outMount[mount]) outMount[mount] = [];
                outMount[mount].push({
                    id: id,
                    dir: ent.dir,
                    entry: (ent.entryPoints && ent.entryPoints["bar-widget"])
                        || eff.entry
                        || "main.qml",
                    mount: mount,
                    after: eff.after || "",
                    before: eff.before || "",
                    settings: {}
                });
            }
            for (const k of Object.keys(outMount))
                if (barMounts[k]) outMount[k] = _sortByRefs(outMount[k]);
        }

        // ---- Non-bar legacy mounts (overlay / bezel / toast) ----
        // shell.json's `plugins[]` array is reserved for these in the
        // future; until then they always come from manifests + the
        // plugins.json fallback. Without this branch, switching to
        // shell.json kills every overlay (launcher, settings-menu,
        // emoji-picker, power-menu, etc.) and bezels (osd) and toasts
        // (notification-toast).
        for (const id of Object.keys(registry)) {
            const eff = _effective(id);
            if (!eff) continue;
            const ent = registry[id];
            if (!ent.installed) continue;
            const mount = eff.mount;
            if (!mount || barMounts[mount]) continue;
            if (!outMount[mount]) outMount[mount] = [];
            outMount[mount].push({
                id: id,
                dir: ent.dir,
                entry: eff.entry || "main.qml",
                mount: mount,
                after: eff.after || "",
                before: eff.before || "",
                settings: {}
            });
        }
        for (const k of Object.keys(outMount))
            if (!barMounts[k]) outMount[k] = _sortByRefs(outMount[k]);

        // ---- byKind (v2 lazy-summon kinds) — independent of bar layout ----
        // shell.json doesn't list overlay/panel/menu plugins in its bar
        // layout; they're enumerated from manifests. Listed here regardless
        // of Config.valid since the lazy hosts use byKind directly.
        for (const id of Object.keys(registry)) {
            const eff = _effective(id);
            if (!eff) continue;
            const ent = registry[id];
            if (!ent.installed) continue;
            if (!ent.v2) continue;
            for (const kind of ent.kinds) {
                if (kind === "bar-widget") continue;  // handled by byMount
                if (!outKind[kind]) outKind[kind] = [];
                outKind[kind].push({
                    id: id,
                    dir: ent.dir,
                    kind: kind,
                    entry: ent.entryPoints[kind] || eff.entry || "main.qml"
                });
            }
        }

        byMount = outMount;
        byKind  = outKind;
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

    // ---- Shell-level IPC ----
    // Single target `shell` with summon/hide/toggle/listPlugins.
    // Individual plugins can still register their own IpcHandler (legacy
    // overlays do); this just adds a uniform entry point for lazy-summon
    // plugins that don't register their own handler.
    property IpcHandler _shellIpc: IpcHandler {
        target: "shell"
        function summon(id: string, payload: string): string {
            const p = (payload && payload.length > 0) ? JSON.parse(payload) : undefined;
            return bus.summon(id, p) ? "ok" : "unknown";
        }
        function hide(id: string): string {
            bus.hide(id);
            return "ok";
        }
        function toggle(id: string, payload: string): string {
            const p = (payload && payload.length > 0) ? JSON.parse(payload) : undefined;
            bus.toggle(id, p);
            return "ok";
        }
        function listPlugins(): string {
            return JSON.stringify(bus.listPlugins());
        }
        function rescanPlugins(): string {
            bus.rescan();
            return "ok";
        }
        function ping(): string { return "ok"; }

        // Top-bar visibility — Omarchy waybar-toggle parity.
        function toggleBar(): string {
            bus.barVisible = !bus.barVisible;
            return bus.barVisible ? "shown" : "hidden";
        }
        function showBar(): string { bus.barVisible = true;  return "ok"; }
        function hideBar(): string { bus.barVisible = false; return "ok"; }
    }

    // Re-derive layout whenever shell.json changes. Config's properties
    // are bindings on top of a FileView reload; we listen on each one
    // so a hand-edit to shell.json refreshes the bar without restart.
    property Connections _configWatch: Connections {
        target: Config
        function onValidChanged()     { bus._rebuild(); }
        function onBarLeftChanged()   { bus._rebuild(); }
        function onBarCenterChanged() { bus._rebuild(); }
        function onBarRightChanged()  { bus._rebuild(); }
    }

    // Boot the first scan once. Subsequent scans go through rescan().
    Component.onCompleted: scanProc.running = true
}
