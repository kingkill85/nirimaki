pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// VPN connection state, driven entirely by JSON files in
// ~/.config/nirimaki/vpns.d/<id>.json. Each declares a status / connect
// / disconnect command set plus an optional `fields[]` schema for per-
// provider settings (account number, tunnel name, preferred region, …)
// — values are interpolated into commands via `{{key}}` substitution
// before exec. {{id}} and {{name}} are auto-injected from the JSON.
//
// NOTE: NetworkManager VPN / WireGuard profiles are NOT aggregated.
// The Add flow in the network panel writes custom JSONs; surfacing NM
// too produced duplicate-looking rows. Users who want NM management
// continue to use `nmcli` or `nm-connection-editor` directly.
//
// Provider PACKAGE install / remove lives in the Settings Menu
// (`Install → Service → <provider>`, `Remove → Service → <provider>`).
// Those scripts install the package + polkit rule only — they do NOT
// create a connection.
//
// Provider CONNECTION add / remove lives in the network panel's VPN
// tab. `addConnection(id, optName)` and `removeProvider(id)` are the
// front-doors. The split keeps "install once per machine" separate
// from "manage N connections per machine".
//
// Public API:
//   VpnService.providers[]            // every active connection (NM + custom)
//   VpnService.activeProviders[]      // .filter(p => p.connected)
//   VpnService.addableProviders[]     // every installed package + whether it's
//                                     //   already registered (drives the panel's
//                                     //   "Add connection" dropdown)
//   VpnService.refresh()
//   VpnService.connect(id) / disconnect(id) / setup(id)
//   VpnService.setFieldValue(id, key, value)
//   VpnService.addConnection(providerId, optName)
//                                     // optName empty → register the .sample as
//                                     //   <providerId>.json (single-instance flow)
//                                     // optName given → create a 2nd/3rd connection
//                                     //   of the same provider (multi-tunnel flow,
//                                     //   wg/openvpn). New id derived from optName.
//   VpnService.removeProvider(id)     // drop a connection
//
// Each providers[] entry:
//   { id, kind: "nm"|"custom", name, icon, connected,
//     statusLabel, canSetup, fields, multiInstance,
//     _config /* opaque */, _path /* source JSON, custom only */ }
QtObject {
    id: root

    property var _customConfigs: []
    property var _customPaths: []
    property var _customStates: ({})
    // feature → installed bool, read from ~/.cache/nirimaki/state.json
    // (maintained by nirimaki-feature-state). Drives the "installed
    // but not registered" detection used by availableForRegistration.
    property var _featureState: ({})

    // Mapping of feature-state key → vpn-provider metadata. Same names
    // today; explicit so future renames don't silently break the join.
    // multiInstance flag tells the UI whether the provider can hold
    // multiple connections (wg/openvpn) or is single-instance (tailscale
    // / pia / netextender — only one daemon / account / wrapper).
    readonly property var _featureToProvider: ({
        tailscale:   { id: "tailscale",   name: "Tailscale",                icon: "󰦝", multiInstance: false },
        wireguard:   { id: "wireguard",   name: "WireGuard",                icon: "󰖂", multiInstance: true  },
        openvpn:     { id: "openvpn",     name: "OpenVPN",                  icon: "󰒃", multiInstance: true  },
        pia:         { id: "pia",         name: "Private Internet Access",  icon: "󰒃", multiInstance: false },
        netextender: { id: "netextender", name: "SonicWall NetExtender",    icon: "󰦝", multiInstance: true  }
    })

    readonly property var providers: {
        const out = [];
        // NetworkManager-managed VPN/WireGuard profiles are intentionally
        // NOT aggregated here. The panel owns its own Add flow that writes
        // vpns.d/*.json — surfacing NM profiles too produced duplicate-
        // looking rows (e.g. one for the NM wireguard connection and one
        // for the wg-quick-driven custom JSON of the same tunnel). Users
        // who want NM management use `nmcli` or `nm-connection-editor`.
        for (let i = 0; i < _customConfigs.length; i++) {
            const cfg = _customConfigs[i];
            const st = _customStates[cfg.id] || { connected: false, statusLabel: "" };
            out.push({
                id:            cfg.id,
                kind:          "custom",
                name:          cfg.name || cfg.id,
                icon:          cfg.icon || "󰦝",
                connected:     !!st.connected,
                statusLabel:   st.statusLabel ||
                               (st.connected ? I18n.t("vpn.state.connected") : I18n.t("vpn.state.disconnected")),
                canSetup:      !!(cfg.setupCmd && cfg.setupCmd.length > 0),
                fields:        cfg.fields || [],
                multiInstance: !!cfg.multiInstance,
                _config:       cfg,
                _path:         _customPaths[i] || ""
            });
        }
        return out;
    }
    readonly property var activeProviders: providers.filter(p => p.connected)

    // Drives the network panel's "Add connection" dropdown. Gates on
    // <name>_configured — only providers where nirimaki's full install
    // (binary + side-effects: polkit rule or systemd service) is done.
    // A provider with only the binary present (e.g. openvpn pulled in
    // as a transitive dep without the polkit rule) doesn't appear,
    // because Connect would either prompt for sudo or silently fail.
    //
    // Single-instance providers drop out once registered; multi-
    // instance ones stay so the user can add more tunnels.
    //
    // Each entry: { id, name, icon, multiInstance, existingCount }
    readonly property var addableProviders: {
        const out = [];
        const counts = {};
        for (const c of _customConfigs) {
            const base = (typeof c.baseId === "string" && c.baseId) ? c.baseId : c.id;
            counts[base] = (counts[base] || 0) + 1;
        }
        for (const feat of Object.keys(_featureToProvider)) {
            if (_featureState[feat + "_configured"] !== true) continue;  // install incomplete
            const meta = _featureToProvider[feat];
            const existing = counts[meta.id] || 0;
            if (!meta.multiInstance && existing > 0) continue; // single-instance, already there
            out.push({
                id:            meta.id,
                name:          meta.name,
                icon:          meta.icon,
                multiInstance: meta.multiInstance,
                existingCount: existing
            });
        }
        return out;
    }

    Component.onCompleted: {
        _scanCustomConfigs();
        refresh();
    }

    function refresh() {
        for (const cfg of _customConfigs) _pollCustomStatus(cfg);
    }

    function connect(id)    { _dispatch(id, "connect"); }
    function disconnect(id) { _dispatch(id, "disconnect"); }
    function setup(id) {
        const p = _findById(id);
        if (!p) return;
        if (p._config.setupCmd && p._config.setupCmd.length > 0) {
            Quickshell.execDetached(_substituteCmd(p._config.setupCmd, p._config));
        }
    }

    function _findById(id) {
        for (const p of providers) if (p.id === id) return p;
        return null;
    }

    function _dispatch(id, op) {
        const p = _findById(id);
        if (!p) return;
        const raw = (op === "connect")
                  ? p._config.connectCmd
                  : p._config.disconnectCmd;
        if (raw && raw.length > 0) {
            Quickshell.execDetached(_substituteCmd(raw, p._config));
            Qt.callLater(() => _pollCustomStatus(p._config));
        }
    }

    // ---- Field substitution ----
    // Resolve {{key}} tokens in every element of an argv array against
    // cfg.fields[].value. Unknown keys are left as literal `{{key}}` so
    // misconfigured templates fail loudly instead of silently exec'ing
    // a command with an empty arg.
    function _substituteCmd(cmd, cfg) {
        const vals = _fieldValues(cfg);
        return cmd.map(arg => _substituteString(arg, vals));
    }

    function _substituteString(s, vals) {
        if (typeof s !== "string") return s;
        return s.replace(/\{\{([A-Za-z0-9_]+)\}\}/g, (m, k) => {
            return (k in vals) ? vals[k] : m;
        });
    }

    function _fieldValues(cfg) {
        const out = {};
        if (!cfg) return out;
        // Expose the connection's id and name so command templates can
        // reference {{id}} (e.g. for keyring lookups under nirimaki-vpn
        // schema with the connection id as attribute) and {{name}}.
        if (typeof cfg.id === "string") out.id = cfg.id;
        if (typeof cfg.name === "string") out.name = cfg.name;
        if (!Array.isArray(cfg.fields)) return out;
        for (const f of cfg.fields) {
            if (!f || typeof f.key !== "string") continue;
            out[f.key] = (f.value !== undefined && f.value !== null) ? String(f.value) : "";
        }
        return out;
    }

    // ---- Custom-provider config discovery ----
    property string _customDir: Quickshell.env("HOME") + "/.config/nirimaki/vpns.d"

    // FolderListModel's count + get() under Qt 6.11 can lag behind
    // actual filesystem state when scanning runs immediately after
    // another file op in the same dir. We keep the model purely as an
    // inotify trigger (its count *eventually* changes on add/remove)
    // but read the on-disk list via a shell `find` whose output is
    // the source of truth.
    property FolderListModel _customDirView: FolderListModel {
        id: customDirView
        folder: "file://" + root._customDir
        showFiles: true
        showDirs: false
        nameFilters: ["*.json"]
        sortField: FolderListModel.Name
        onCountChanged: root._scanCustomConfigs()
    }

    // Single-flight guard. Rapid clicks (Remove → Register, or two
    // Removes in a row) trigger multiple _scanCustomConfigs calls
    // before listProc finishes — reassigning command/running while
    // the process is alive is undefined behaviour per Quickshell.Io.
    // We track pending and replay once the current run completes.
    property bool _scanPending: false

    function _scanCustomConfigs() {
        if (listProc.running) {
            _scanPending = true;
            return;
        }
        listProc.command = ["sh", "-lc",
            "find " + _shQuote(_customDir)
              + " -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort"];
        listProc.collected = "";
        listProc.running = true;
    }

    property Process _listProc: Process {
        id: listProc
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => listProc.collected += data + "\n"
        }
        onExited: {
            const files = listProc.collected.split("\n")
                .map(s => s.trim())
                .filter(s => s.length > 0);
            root._loadCustomFiles(files);
            if (root._scanPending) {
                root._scanPending = false;
                Qt.callLater(root._scanCustomConfigs);
            }
        }
    }

    // Single-flight on loadProc too. If a load is in flight and the
    // file set changes, queue the new request; replay after the in-
    // flight one completes so we don't race onto stale paths.
    property var _pendingLoad: null

    function _loadCustomFiles(paths) {
        if (paths.length === 0) {
            _customConfigs = [];
            _customPaths = [];
            return;
        }
        if (loadProc.running) {
            _pendingLoad = paths;
            return;
        }
        const sep = "\n__NIRIMAKI_VPN_FILE_SEP__\n";
        loadProc.paths = paths;
        loadProc.collected = "";
        loadProc.command = ["sh", "-lc",
            paths.map(p => "cat " + _shQuote(p) + " && printf '" + sep + "'").join(" && ")];
        loadProc.running = true;
    }

    property Process _loadProc: Process {
        id: loadProc
        property var paths: []
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => loadProc.collected += data + "\n"
        }
        onExited: {
            const sep = "\n__NIRIMAKI_VPN_FILE_SEP__\n";
            const chunks = loadProc.collected.split(sep);
            const outCfg = [];
            const outPaths = [];
            for (let i = 0; i < loadProc.paths.length; i++) {
                const raw = chunks[i] || "";
                if (!raw.trim()) continue;
                try {
                    const cfg = JSON.parse(raw);
                    if (!cfg.id) continue;
                    outCfg.push(cfg);
                    outPaths.push(loadProc.paths[i]);
                } catch (e) {
                    console.warn("VpnService: bad json in", loadProc.paths[i], "—", e.toString());
                }
            }
            root._customConfigs = outCfg;
            root._customPaths   = outPaths;
            for (const cfg of outCfg) root._pollCustomStatus(cfg);
            if (root._pendingLoad !== null) {
                const next = root._pendingLoad;
                root._pendingLoad = null;
                Qt.callLater(() => root._loadCustomFiles(next));
            }
        }
    }

    function _shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // ---- Custom-provider status polling ----
    property var _pollQueue: []
    property bool _pollBusy: false

    function _pollCustomStatus(cfg) {
        _pollQueue.push({ id: cfg.id, phase: "status" });
        _drainPollQueue();
    }

    function _drainPollQueue() {
        if (_pollBusy) return;
        const next = _pollQueue.shift();
        if (!next) return;
        const cfg = _customConfigs.find(c => c.id === next.id);
        if (!cfg) { _drainPollQueue(); return; }

        let cmd = null;
        if (next.phase === "status")     cmd = cfg.statusCmd;
        else if (next.phase === "label") cmd = cfg.statusLabelCmd;
        if (!Array.isArray(cmd) || cmd.length === 0) {
            _drainPollQueue();
            return;
        }
        pollProc._currentId = next.id;
        pollProc._currentPhase = next.phase;
        pollProc.collected = "";
        pollProc.command = _substituteCmd(cmd, cfg);
        _pollBusy = true;
        pollProc.running = true;
    }

    property Process _pollProc: Process {
        id: pollProc
        property string _currentId: ""
        property string _currentPhase: ""
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => pollProc.collected += data + "\n"
        }
        onExited: {
            const id    = pollProc._currentId;
            const phase = pollProc._currentPhase;
            const text  = pollProc.collected.replace(/\n+$/, "");
            const cfg   = root._customConfigs.find(c => c.id === id);
            if (!cfg) { root._pollBusy = false; root._drainPollQueue(); return; }

            const next = Object.assign({}, root._customStates);
            const prev = next[id] || { connected: false, statusLabel: "" };

            if (phase === "status") {
                const re = new RegExp(cfg.statusOnPattern || "", "im");
                const connected = re.test(text);
                next[id] = { connected: connected, statusLabel: prev.statusLabel };
                root._customStates = next;
                if (connected && Array.isArray(cfg.statusLabelCmd) && cfg.statusLabelCmd.length > 0) {
                    root._pollQueue.unshift({ id: id, phase: "label" });
                }
            } else if (phase === "label") {
                const label = text.split("\n")[0].trim();
                next[id] = { connected: prev.connected, statusLabel: label };
                root._customStates = next;
            }

            root._pollBusy = false;
            root._drainPollQueue();
        }
    }

    property Timer _customPollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            for (const cfg of root._customConfigs) root._pollCustomStatus(cfg);
        }
    }

    property Timer _postOpRefresh: Timer {
        id: postOpRefresh
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    // ---- Field-value write-back ----
    // Persist one or more field values back into the source JSON. Uses
    // jq for a structural in-place edit so unrelated keys (statusCmd,
    // _comment, …) stay byte-identical. After mv-into-place we force a
    // _scanCustomConfigs so providers[] reflects the new value
    // immediately (FolderListModel doesn't fire on file modifications).
    //
    // setFieldValue takes ONE field — kept for back-compat.
    // setFieldValues takes a {key: value, …} map and writes all in a
    // single jq invocation. Use this from the Configure form's Save.
    function setFieldValue(id, key, value) {
        const updates = {};
        updates[key] = value;
        setFieldValues(id, updates);
    }

    function setFieldValues(id, updates) {
        const idx = _customConfigs.findIndex(c => c.id === id);
        if (idx < 0) {
            console.warn("VpnService.setFieldValues: unknown id", id);
            return;
        }
        const path = _customPaths[idx];
        if (!path) return;
        const keys = Object.keys(updates || {});
        if (keys.length === 0) return;
        if (saveProc.running) {
            // A previous save is still in flight — queue this one.
            // Last-writer-wins: we just stash the latest updates map.
            _pendingSave = { id: id, updates: Object.assign({}, _pendingSave ? _pendingSave.updates : {}, updates) };
            return;
        }
        // Build a jq filter that applies all key→value replacements in
        // a single pipeline. --arg pairs are passed per key as kN/vN
        // and the filter walks fields[] once per pair.
        let jqArgs = "";
        let jqFilter = "(.fields // [])";
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            const v = String(updates[k]);
            jqArgs += " --arg k" + i + " " + _shQuote(k);
            jqArgs += " --arg v" + i + " " + _shQuote(v);
            jqFilter += " | map(if .key == $k" + i + " then .value = $v" + i + " else . end)";
        }
        jqFilter += " | (. as $f | {fields: $f})";
        saveProc.command = ["sh", "-lc",
            "jq " + jqArgs + " '. + (" + jqFilter + ")' "
              + _shQuote(path)
              + " > " + _shQuote(path + ".tmp")
              + " && mv " + _shQuote(path + ".tmp") + " " + _shQuote(path)];
        saveProc.running = true;
    }

    property var _pendingSave: null

    // ---- Secret write-back ----
    // Update the keyring entry for a connection. Secret fields (type:
    // "secret") are stored under schema "nirimaki-vpn" with the
    // connection id as attribute; connectCmd looks them up via
    // secret-tool. Password is base64-encoded into the shell command
    // so it doesn't appear verbatim in argv / /proc/<pid>/cmdline.
    function updateSecret(id, password) {
        if (!password || password.length === 0) return;
        const cfg = _customConfigs.find(c => c.id === id);
        if (!cfg) {
            console.warn("VpnService.updateSecret: unknown id", id);
            return;
        }
        const pwB64 = Qt.btoa(password);
        const label = "NetExtender (" + (cfg.name || id) + ")";
        Quickshell.execDetached(["bash", "-c",
            "printf '%s' " + _shQuote(pwB64) + " | base64 -d"
          + " | secret-tool store --label=" + _shQuote(label)
              + " nirimaki-vpn " + _shQuote(id)]);
    }

    property Process _saveProc: Process {
        id: saveProc
        property string err: ""
        stderr: SplitParser { onRead: (data) => { saveProc.err += data + "\n"; console.warn("VpnService.save stderr:", data); } }
        onExited: (code, status) => {
            if (code !== 0) console.warn("VpnService.save failed code=", code, "err=", saveProc.err);
            saveProc.err = "";
            root._scanCustomConfigs();
            // Replay any save that arrived while we were running.
            if (root._pendingSave) {
                const next = root._pendingSave;
                root._pendingSave = null;
                Qt.callLater(() => root.setFieldValues(next.id, next.updates));
            }
        }
    }

    // ---- Dropdown field options ----
    // A fields[] entry with type:"dropdown" + optionsCmd carries a
    // populate-on-demand list. The Configure editor calls
    // loadFieldOptions(id, key) on open; we run optionsCmd and stash
    // the lines in _fieldOptions[id][key]. The editor binds Dropdown.model
    // to getFieldOptions(id, key).
    property var _fieldOptions: ({})

    function getFieldOptions(providerId, key) {
        const byProvider = _fieldOptions[providerId] || {};
        return byProvider[key] || [];
    }

    function loadFieldOptions(providerId, key) {
        // Duck-type instead of Array.isArray — values cross QML
        // property-var boundaries which strips the JS-array tag, so
        // Array.isArray returns false even on real arrays.
        const cfg = _customConfigs.find(c => c.id === providerId);
        if (!cfg || !cfg.fields || !cfg.fields.length) return;
        const field = cfg.fields.find(f => f && f.key === key);
        if (!field || !field.optionsCmd || !field.optionsCmd.length) return;
        // Skip if already loaded recently. Cheap memoisation per session.
        const existing = (_fieldOptions[providerId] || {})[key];
        if (existing && existing.length > 0) return;
        // Tag the in-flight request so onExited knows which slot to fill.
        optionsProc._currentProvider = providerId;
        optionsProc._currentKey = key;
        optionsProc.collected = "";
        optionsProc.command = _substituteCmd(field.optionsCmd, cfg);
        optionsProc.running = true;
    }

    property Process _optionsProc: Process {
        id: optionsProc
        property string _currentProvider: ""
        property string _currentKey: ""
        property string collected: ""
        stdout: SplitParser { onRead: (data) => optionsProc.collected += data + "\n" }
        onExited: (code, status) => {
            const provider = optionsProc._currentProvider;
            const key = optionsProc._currentKey;
            if (code !== 0) { console.warn("VpnService.optionsCmd failed code=", code, "for", provider, key); }
            const lines = optionsProc.collected.split("\n")
                .map(s => s.trim())
                .filter(s => s.length > 0);
            const next = Object.assign({}, root._fieldOptions);
            next[provider] = Object.assign({}, next[provider] || {});
            next[provider][key] = lines;
            root._fieldOptions = next;
        }
    }

    // ---- Per-connection remove ----
    // Three-step teardown:
    //   1. disconnectCmd  (custom only) — bring the tunnel down
    //   2. removeCmd      (custom only) — provider-specific wipe that
    //      goes beyond `down` (e.g. `tailscale logout` so a future Add
    //      starts from a clean device-auth flow)
    //   3. drop the JSON / nmcli profile
    //
    // After the rm we also call vpn_pill_remove_if_empty so the bar pill
    // disappears when nothing remains. The single-flight guard prevents
    // a second Remove click from corrupting the running shell-out.
    property bool _removing: false
    function removeProvider(id) {
        if (_removing) {
            console.warn("VpnService.removeProvider: already running, ignoring", id);
            return;
        }
        const p = _findById(id);
        if (!p) {
            console.warn("VpnService.removeProvider: no provider with id", id);
            return;
        }
        if (!p._path) {
            console.warn("VpnService.removeProvider: empty _path for custom provider", id);
            return;
        }
        // Phase 1+2: down + wipe (fire-and-forget — failures shouldn't
        // block the file delete, the user can clean manually if needed).
        const dc = p._config.disconnectCmd;
        if (dc && dc.length > 0) {
            Quickshell.execDetached(_substituteCmd(dc, p._config));
        }
        const rc = p._config.removeCmd;
        if (rc && rc.length > 0) {
            Quickshell.execDetached(_substituteCmd(rc, p._config));
        }
        _removing = true;
        const helper = Quickshell.env("HOME") + "/.local/bin/nirimaki-vpn-provider-helpers";
        removeProc.command = ["bash", "-c",
            "rm -fv " + _shQuote(p._path)
          + " && . " + _shQuote(helper)
          + " && vpn_pill_remove_if_empty"];
        removeProc.running = true;
    }

    property Process _removeProc: Process {
        id: removeProc
        property string err: ""
        stdout: SplitParser { onRead: (data) => console.log("VpnService.remove:", data) }
        stderr: SplitParser { onRead: (data) => { removeProc.err += data + "\n"; console.warn("VpnService.remove stderr:", data); } }
        onExited: (code, status) => {
            if (code !== 0) console.warn("VpnService.remove failed code=", code, "err=", removeProc.err);
            removeProc.err = "";
            root._removing = false;
            // Force a vpns.d rescan so providers[] reflects the deletion
            // immediately — don't depend on FolderListModel's inotify lag.
            root._scanCustomConfigs();
            postOpRefresh.start();
        }
    }

    // ---- Add a connection ----
    // One method per provider. All Adds are fire-and-forget via
    // _runAdd, which redirects helper stdout+stderr to
    // ~/.cache/nirimaki/vpn-add.log so silent failures can be tailed
    // instead of vanishing.

    readonly property string _addLog: Quickshell.env("HOME") + "/.cache/nirimaki/vpn-add.log"

    function _runAdd(body) {
        const helper = Quickshell.env("HOME") + "/.local/bin/nirimaki-vpn-provider-helpers";
        const cache = Quickshell.env("HOME") + "/.cache/nirimaki";
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p " + _shQuote(cache)
          + " && { echo '--- ' \"$(date +'%Y-%m-%d %H:%M:%S')\" ' ---'; "
          + ". " + _shQuote(helper) + " && vpn_locate_repo && " + body + "; "
          + "echo \"(exit $?)\"; } >> " + _shQuote(_addLog) + " 2>&1"]);
    }

    function addTailscale() {
        _runAdd("vpn_add_tailscale");
    }

    function addPia(username, password) {
        const cache = Quickshell.env("HOME") + "/.cache/nirimaki";
        const blob = username + "\n" + password + "\n";
        const blobB64 = Qt.btoa(blob);
        _runAdd(
            "credfile=$(mktemp " + _shQuote(cache) + "/.pia-login-XXXXXX)"
          + " && chmod 600 \"$credfile\""
          + " && printf '%s' " + _shQuote(blobB64) + " | base64 -d > \"$credfile\""
          + " && vpn_add_pia \"$credfile\"");
    }

    function addWireguard(connName, tunnel) {
        _runAdd("vpn_add_wireguard " + _shQuote(connName) + " " + _shQuote(tunnel));
    }

    function addOpenvpn(connName, profile) {
        _runAdd("vpn_add_openvpn " + _shQuote(connName) + " " + _shQuote(profile));
    }

    // Password goes through a 0600 tempfile under ~/.cache/nirimaki/
    // — base64-encoded into the shell command so it never appears
    // verbatim in argv. The helper reads the tempfile then unlinks it.
    function addNetextender(connName, server, domain, username, password) {
        const cache = Quickshell.env("HOME") + "/.cache/nirimaki";
        const pwB64 = Qt.btoa(password);
        _runAdd(
            "pwfile=$(mktemp " + _shQuote(cache) + "/.netex-pw-XXXXXX)"
          + " && chmod 600 \"$pwfile\""
          + " && printf '%s' " + _shQuote(pwB64) + " | base64 -d > \"$pwfile\""
          + " && vpn_add_netextender "
              + _shQuote(connName) + " "
              + _shQuote(server) + " "
              + _shQuote(domain) + " "
              + _shQuote(username) + " \"$pwfile\"");
    }


    // ---- Feature-state watcher ----
    // nirimaki-feature-state writes ~/.cache/nirimaki/state.json at
    // session start + after every install/remove helper. FileView's
    // watchChanges catches the rewrite (mv-into-place is atomic from
    // inotify's POV).
    property FileView _stateFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/nirimaki/state.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text() || "{}");
                root._featureState = parsed;
            } catch (e) {
                root._featureState = ({});
            }
        }
        onLoadFailed: { root._featureState = ({}); }
        onFileChanged: reload()
    }
}
