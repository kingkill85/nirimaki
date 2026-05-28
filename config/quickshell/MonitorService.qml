pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Singleton wrapping `niri msg outputs`. Plugins read the reactive
// `outputs` list and call applyConfig / revert to drive monitors.kdl.
//
// niri's event-stream has no output-changed event, so we re-poll on:
//   - `refresh()` (called explicitly when a UI surface opens),
//   - the ConfigLoaded event from NiriService (so applying a new
//     monitors.kdl auto-refreshes us),
//   - any external write to monitors.kdl picked up by FileView.
//
//   MonitorService.outputs        // [{id, name, make, model, serial,
//                                  //   modes, currentMode, scale,
//                                  //   position, transform, vrr,
//                                  //   vrrSupported, widthPx, heightPx}]
//   MonitorService.busy           // poll in flight
//   MonitorService.applying       // applyConfig wrote and is awaiting reload
//
//   MonitorService.refresh()                 // re-poll
//   MonitorService.snapshot()                // current outputs as a plain object
//   MonitorService.applyConfig(snapshot)     // write monitors.kdl + reload
//   MonitorService.revert()                  // restore the last backup + reload
//   MonitorService.hasBackup                 // there's something to revert to
//   MonitorService.identifier(o)             // EDID string used in monitors.kdl
//   MonitorService.modeLabel(m)              // "1920x1080@60.000Hz"
//   MonitorService.fmtRefresh(milliHz)       // "60.000"
QtObject {
    id: root

    // ---- Public state ----
    property var outputs: []
    property bool busy: false
    property bool applying: false

    // Backup of the last-known-good monitors.kdl contents, captured
    // just before applyConfig writes a new version. revert() pushes
    // this back to disk + asks niri to reload. Empty string == no
    // backup yet (first apply of the session).
    property string _backup: ""
    readonly property bool hasBackup: _backup.length > 0

    // Map of output-identifier → raw KDL of any child nodes the panel
    // doesn't manage (everything except mode/scale/transform/position/
    // variable-refresh-rate). Re-emitted verbatim inside the rewritten
    // output block so a user can hand-edit `layout { ... }` or other
    // niri output settings without the panel clobbering them on Apply.
    property var _lastExtras: ({})

    // Live extras for an output. Looks up by EDID identifier first
    // (the form `nirimaki monitors panel` writes), then by connector
    // name (the form a user is more likely to type by hand). Returns
    // empty string when the output has no hand-edits.
    function extrasFor(id, connector) {
        if (id        && _lastExtras[id])        return _lastExtras[id];
        if (connector && _lastExtras[connector]) return _lastExtras[connector];
        return "";
    }

    readonly property string monitorsPath:
        Quickshell.env("HOME") + "/.config/niri/monitors.kdl"

    // ---- Refresh / parsing ----
    function refresh() {
        if (busy) return;
        busy = true;
        pollProc.collected = "";
        pollProc.running = true;
    }

    function _parseOutputs(json) {
        let data;
        try { data = JSON.parse(json); } catch (e) {
            console.warn("MonitorService: failed to parse outputs:", e.toString());
            return [];
        }
        const out = [];
        for (const name in data) {
            const o = data[name];
            const logical = o.logical || {};
            const modes = Array.isArray(o.modes) ? o.modes : [];
            const cur = (typeof o.current_mode === "number" && modes[o.current_mode])
                      ? modes[o.current_mode] : null;
            out.push({
                // Canonical key for this monitor in monitors.kdl. Niri
                // accepts either the connector ("DP-3") or the EDID
                // identifier; the latter survives port-swaps so we
                // prefer it when serial is present, fall back to the
                // make/model pair, and finally to the connector name.
                id: _edidIdentifier(o) || name,
                connector: name,
                make:   o.make   || "",
                model:  o.model  || "",
                serial: o.serial || "",
                modes:  modes,
                currentMode:  o.current_mode || 0,
                vrrSupported: !!o.vrr_supported,
                vrr:          !!o.vrr_enabled,
                scale:     logical.scale || 1.0,
                positionX: logical.x || 0,
                positionY: logical.y || 0,
                widthPx:   logical.width  || (cur ? cur.width  : 0),
                heightPx:  logical.height || (cur ? cur.height : 0),
                transform: logical.transform || "Normal"
            });
        }
        // Sort by current position so the canvas indexes match a left-
        // to-right reading order; ties broken by connector name.
        out.sort((a, b) => {
            if (a.positionX !== b.positionX) return a.positionX - b.positionX;
            return a.connector.localeCompare(b.connector);
        });
        return out;
    }

    function _edidIdentifier(o) {
        const parts = [];
        if (o.make)   parts.push(o.make);
        if (o.model)  parts.push(o.model);
        if (o.serial) parts.push(o.serial);
        return parts.join(" ");
    }

    // ---- Snapshot / apply / revert ----
    // Plain JS object so the panel can mutate it freely without
    // touching the live `outputs` list.
    function snapshot() {
        return outputs.map(o => ({
            id:        o.id,
            connector: o.connector,
            // Carry through the full mode list so the panel can populate
            // its dropdown without reaching back into MonitorService.
            modes:     o.modes,
            modeIndex: o.currentMode,
            widthPx:   o.widthPx,
            heightPx:  o.heightPx,
            scale:     o.scale,
            positionX: o.positionX,
            positionY: o.positionY,
            transform: o.transform,
            vrr:          o.vrr,
            vrrSupported: o.vrrSupported,
            // Resolved mode object so the writer can render the
            // `mode "WxH@R"` line without re-indexing.
            mode: o.modes[o.currentMode] || null,
            // Per-output hand-edits the panel doesn't model (raw KDL
            // pasted into the Custom-KDL textbox). Pre-filled from the
            // current monitors.kdl so the textbox shows existing
            // edits; the panel writes back here and applyConfig
            // round-trips it.
            extras: extrasFor(o.id, o.connector)
        }));
    }

    // Build the monitors.kdl text from a snapshot, capture the old
    // contents into the backup slot, write atomically, and let niri's
    // own file-watcher reload. Returns true on write success.
    function applyConfig(snap) {
        applying = true;
        // Capture the current file as the revert target. Read via
        // FileView synchronously by reload()+text() since the FileView
        // already watches this path; but to keep the write path
        // self-contained we shell out to `cat` via Process.
        readBackupProc.snap = snap;
        readBackupProc.command = ["cat", monitorsPath];
        readBackupProc.running = true;
    }

    function _afterBackupRead(snap) {
        // Preserve any hand-edited output children that the panel
        // doesn't model (e.g. per-output `layout { default-column-width
        // ... }`). Parsed from the file we just backed up, keyed by the
        // exact identifier string in the KDL header.
        _lastExtras = _parseExtras(_backup);
        const text = _renderKdl(snap);
        writeProc.command = ["sh", "-lc",
            "set -e; tmp=$(mktemp \"" + monitorsPath + ".XXXXXX\"); " +
            "cat > \"$tmp\" <<'NIRIMAKI_MONITORS_EOF'\n" + text + "\nNIRIMAKI_MONITORS_EOF\n" +
            "mv -- \"$tmp\" \"" + monitorsPath + "\""];
        writeProc.running = true;
    }

    function revert() {
        if (!hasBackup) return false;
        applying = true;
        const text = _backup;
        writeProc.command = ["sh", "-lc",
            "set -e; tmp=$(mktemp \"" + monitorsPath + ".XXXXXX\"); " +
            "cat > \"$tmp\" <<'NIRIMAKI_MONITORS_EOF'\n" + text + "\nNIRIMAKI_MONITORS_EOF\n" +
            "mv -- \"$tmp\" \"" + monitorsPath + "\""];
        writeProc.running = true;
        // Clear backup after revert — same backup shouldn't be used
        // twice (the next apply will capture a fresh one).
        _backup = "";
        return true;
    }

    function clearBackup() { _backup = ""; }

    // ---- KDL writer ----
    // Render the snapshot to monitors.kdl text. V1 fully regenerates
    // the file — niri's monitors.kdl is small and the user has the
    // panel as the source of truth from here on. Comments outside
    // `output` blocks are preserved by emitting a header comment +
    // re-inserting any user-prefix content captured in _userPreamble.
    function _renderKdl(snap) {
        const lines = [
            "// monitors.kdl — managed by the Nirimaki monitors panel.",
            "// You can still hand-edit this file; the panel will pick",
            "// up your changes on next open.",
            ""
        ];
        // Normalize the layout to the origin: niri expects a contiguous
        // arrangement anchored at (0,0). The drag canvas works in centered
        // coordinates, so a freely-dragged layout can float with no output
        // at the origin — which makes pointer transitions land oddly. Shift
        // every output by the layout's min corner so the top-left monitor
        // sits at 0,0 (shape is preserved; only the origin moves).
        let minX = Infinity, minY = Infinity;
        for (const m of snap) {
            if (m.positionX < minX) minX = m.positionX;
            if (m.positionY < minY) minY = m.positionY;
        }
        if (!isFinite(minX)) minX = 0;
        if (!isFinite(minY)) minY = 0;
        for (const m of snap) {
            const mode = m.mode;
            lines.push("output \"" + _escape(m.id) + "\" {");
            if (mode) {
                lines.push("    mode \"" + mode.width + "x" + mode.height +
                           "@" + fmtRefresh(mode.refresh_rate) + "\"");
            }
            lines.push("    scale " + _fmtScale(m.scale));
            // Niri's "Normal" transform is the default — omit so the
            // file stays tidy for monitors that don't need it. The
            // JSON form is CamelCase ("Flipped270") while the kdl
            // form is kebab-case ("flipped-270"); translate here.
            if (m.transform && m.transform !== "Normal") {
                lines.push("    transform \"" + _transformToKdl(m.transform) + "\"");
            }
            lines.push("    position x=" + Math.round(m.positionX - minX) +
                       " y=" + Math.round(m.positionY - minY));
            if (m.vrr) lines.push("    variable-refresh-rate");
            // Re-emit hand-edits. The snapshot's `extras` field wins
            // (so the panel's Custom-KDL textbox is authoritative when
            // present); otherwise fall back to whatever the live file
            // had — keyed by EDID identifier first, connector name as
            // a backup, covering either form a user may have typed.
            let extra = (typeof m.extras === "string") ? m.extras
                      : (_lastExtras[m.id] || _lastExtras[m.connector] || "");
            extra = String(extra).replace(/^\n+|\n+$/g, "");
            if (extra) {
                // The textbox stores extras dedented (no leading column
                // of indentation), so a four-space prefix on every
                // non-empty line is what nests the block inside its
                // owning `output { }`. Relative indentation typed by
                // the user is preserved on top.
                const indented = extra.split("\n").map(l =>
                    l.length === 0 ? l : ("    " + l)
                ).join("\n");
                lines.push(indented);
            }
            lines.push("}");
            lines.push("");
        }
        return lines.join("\n");
    }

    // Walk monitors.kdl and extract, for every `output "<name>" { ... }`
    // block, the raw text of every child node that isn't a panel-managed
    // field. Returned text is pre-indented with four spaces and ready
    // to drop back inside a rewritten output block. Brace counting is
    // depth-aware so nested blocks (`layout { default-column-width
    // { proportion 1.0; } }`) survive intact.
    readonly property var _managedFields: ({
        "mode": true, "scale": true, "transform": true,
        "position": true, "variable-refresh-rate": true
    })
    function _parseExtras(text) {
        const out = {};
        if (!text) return out;
        const re = /output\s+"((?:[^"\\]|\\.)*)"\s*\{/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            const name = m[1].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
            let i = re.lastIndex;
            let depth = 1;
            const start = i;
            while (i < text.length && depth > 0) {
                const c = text[i];
                if (c === "{") depth++;
                else if (c === "}") depth--;
                if (depth > 0) i++;
            }
            const body = text.substring(start, i);
            re.lastIndex = i + 1;
            const kept = [];
            const lines = body.split("\n");
            let j = 0;
            while (j < lines.length) {
                const line = lines[j];
                const trimmed = line.trim();
                if (trimmed === "" || trimmed.startsWith("//")) { j++; continue; }
                const firstTok = trimmed.split(/\s|\{/)[0];
                const managed = root._managedFields[firstTok] === true;
                // Compute the nested-block depth this line opens — so
                // both managed AND preserved entries can span multiple
                // lines correctly.
                let d = (line.match(/\{/g) || []).length
                      - (line.match(/\}/g) || []).length;
                if (!managed) kept.push(line);
                j++;
                while (d > 0 && j < lines.length) {
                    const ln = lines[j];
                    d += (ln.match(/\{/g) || []).length
                       - (ln.match(/\}/g) || []).length;
                    if (!managed) kept.push(ln);
                    j++;
                }
            }
            if (kept.length > 0) {
                // Strip leading/trailing blank lines but keep interior
                // formatting the user picked.
                while (kept.length && kept[0].trim() === "") kept.shift();
                while (kept.length && kept[kept.length - 1].trim() === "") kept.pop();
                if (kept.length) {
                    // Dedent by the shortest leading-whitespace run
                    // among non-empty lines, so the textbox shows the
                    // block flush-left. The writer re-applies the
                    // four-space prefix when it rebuilds the file.
                    let minIndent = Infinity;
                    for (const ln of kept) {
                        if (ln.trim() === "") continue;
                        const lead = ln.match(/^[ \t]*/)[0].length;
                        if (lead < minIndent) minIndent = lead;
                    }
                    if (minIndent > 0 && minIndent !== Infinity) {
                        for (let k = 0; k < kept.length; k++) {
                            kept[k] = kept[k].slice(minIndent);
                        }
                    }
                    out[name] = kept.join("\n");
                }
            }
        }
        return out;
    }

    // niri JSON ↔ niri kdl transform spelling:
    //   "Normal"     ↔ "normal"
    //   "90"/"180"/"270" identical
    //   "FlippedN"   ↔ "flipped-N"
    //   "Flipped"    ↔ "flipped"
    readonly property var _transformsJsonToKdl: ({
        "Normal":     "normal",
        "90":         "90",
        "180":        "180",
        "270":        "270",
        "Flipped":    "flipped",
        "Flipped90":  "flipped-90",
        "Flipped180": "flipped-180",
        "Flipped270": "flipped-270"
    })
    function _transformToKdl(t) {
        return _transformsJsonToKdl[t] !== undefined ? _transformsJsonToKdl[t] : "normal";
    }

    function _escape(s) {
        // KDL string literals: escape backslash + quote. Niri's parser
        // doesn't support \n inside the identifier so we replace it
        // with a space to stay safe.
        return String(s).replace(/\\/g, "\\\\")
                        .replace(/"/g, '\\"')
                        .replace(/\n/g, " ");
    }

    function _fmtScale(s) {
        // Render integer scales without a trailing `.0` — niri accepts
        // both, but `scale 1` matches the convention in the seed file.
        return (s === Math.round(s)) ? String(s|0) : String(s);
    }

    // ---- Display helpers ----
    function fmtRefresh(milliHz) {
        if (!milliHz) return "0";
        return (milliHz / 1000).toFixed(3);
    }

    function modeLabel(m) {
        if (!m) return "";
        return m.width + "×" + m.height + " @ " + fmtRefresh(m.refresh_rate) + " Hz";
    }

    function identifier(o) { return o ? o.id : ""; }

    // ---- Processes ----
    // Live watch of monitors.kdl so `_lastExtras` is up-to-date the
    // moment the panel opens (instead of only after the first Apply).
    // niri's own file-watcher reloads on writes, so this FileView and
    // niri see the same file in the same order.
    property FileView _monitorsFile: FileView {
        path: root.monitorsPath
        watchChanges: true
        printErrors: false
        onLoaded: { root._lastExtras = root._parseExtras(text() || ""); }
        onLoadFailed: { root._lastExtras = ({}); }
    }

    property Process _pollProc: Process {
        id: pollProc
        property string collected: ""
        command: ["niri", "msg", "--json", "outputs"]
        stdout: SplitParser {
            onRead: (data) => pollProc.collected += data + "\n"
        }
        onExited: {
            root.outputs = root._parseOutputs(pollProc.collected);
            root.busy = false;
        }
    }

    property Process _readBackupProc: Process {
        id: readBackupProc
        property var snap: null
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => readBackupProc.collected += data + "\n"
        }
        onExited: {
            // Drop the trailing newline injected by SplitParser. If the
            // file didn't exist, exit code is non-zero but collected is
            // empty; either way we proceed with an empty backup so the
            // user can still revert to "no file" (niri falls back to
            // its built-in defaults).
            root._backup = readBackupProc.collected.replace(/\n$/, "");
            root._afterBackupRead(readBackupProc.snap);
        }
    }

    property Process _writeProc: Process {
        id: writeProc
        onExited: {
            root.applying = false;
            // niri's own file-watcher will pick up the new contents
            // and reload. We re-poll outputs after a short delay so
            // the panel sees the post-reload values.
            postWriteRefresh.start();
        }
    }

    property Timer _postWriteRefresh: Timer {
        id: postWriteRefresh
        interval: 600
        repeat: false
        onTriggered: root.refresh()
    }

    // ---- Initial fetch ----
    Component.onCompleted: refresh()
}
