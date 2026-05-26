pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Aggregated VPN state across two sources:
//
//   1. NetworkManager VPN / WireGuard profiles — discovered via
//      `nmcli connection show`. Active state = STATE column is
//      `activated`. Connect / disconnect run `nmcli connection up|down`.
//
//   2. Custom providers — one JSON file per provider under
//      ~/.config/nirimaki/vpns.d/<id>.json:
//
//      {
//        "id": "pia",
//        "name": "Private Internet Access",
//        "icon": "󰒃",
//        "statusCmd":        ["piactl", "get", "connectionstate"],
//        "statusOnPattern":  "^Connected$",
//        "statusLabelCmd":   ["piactl", "get", "region"],   // optional
//        "connectCmd":       ["piactl", "connect"],
//        "disconnectCmd":    ["piactl", "disconnect"],
//        "setupCmd":         ["pia-client"],                 // optional
//        "pollSeconds":      5
//      }
//
//      Polled every pollSeconds. statusOnPattern is a regex matched
//      case-insensitively against statusCmd's stdout. statusLabelCmd
//      is optional and only invoked while connected.
//
// Public API:
//   VpnService.providers[]        // unified list
//   VpnService.activeProviders[]  // .filter(p => p.connected)
//   VpnService.refresh()          // re-poll everything
//   VpnService.connect(id)
//   VpnService.disconnect(id)
//   VpnService.setup(id)          // launches the provider's own
//                                 // configuration tool (setupCmd)
//
// Each providers[] entry looks like:
//   { id, kind: "nm"|"custom", name, icon, connected,
//     statusLabel, canSetup, _config /* opaque */ }
QtObject {
    id: root

    // ---- Sources ----
    // NM: list of { name, type, active } parsed from `nmcli`.
    property var _nmConnections: []
    // Custom: list of provider config objects loaded from vpns.d.
    property var _customConfigs: []
    // Custom: map of id → { connected: bool, statusLabel: string }
    property var _customStates: ({})

    // Output of the unified view used by the bar pill + popover.
    readonly property var providers: {
        const out = [];
        // NM first (alphabetical), then custom (file-discovery order).
        const nm = _nmConnections.slice().sort((a, b) => a.name.localeCompare(b.name));
        for (const c of nm) {
            out.push({
                id:          "nm:" + c.name,
                kind:        "nm",
                name:        c.name,
                icon:        _iconForNmType(c.type),
                connected:   !!c.active,
                statusLabel: c.active ? I18n.t("vpn.state.connected") : I18n.t("vpn.state.disconnected"),
                canSetup:    true,    // nm-connection-editor
                _config:     c
            });
        }
        for (const cfg of _customConfigs) {
            const st = _customStates[cfg.id] || { connected: false, statusLabel: "" };
            out.push({
                id:          cfg.id,
                kind:        "custom",
                name:        cfg.name || cfg.id,
                icon:        cfg.icon || "󰦝",
                connected:   !!st.connected,
                statusLabel: st.statusLabel ||
                             (st.connected ? I18n.t("vpn.state.connected") : I18n.t("vpn.state.disconnected")),
                canSetup:    Array.isArray(cfg.setupCmd) && cfg.setupCmd.length > 0,
                _config:     cfg
            });
        }
        return out;
    }
    readonly property var activeProviders: providers.filter(p => p.connected)

    // ---- Lifecycle ----
    Component.onCompleted: {
        _scanCustomConfigs();
        refresh();
    }

    function refresh() {
        // NM source.
        nmListProc.collected = "";
        nmListProc.command = ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"];
        nmListProc.running = true;
        // Custom sources: kick a status poll for each one.
        for (const cfg of _customConfigs) _pollCustomStatus(cfg);
    }

    function connect(id)    { _dispatch(id, "connect"); }
    function disconnect(id) { _dispatch(id, "disconnect"); }
    function setup(id) {
        const p = _findById(id);
        if (!p) return;
        if (p.kind === "nm") {
            Quickshell.execDetached(["nm-connection-editor"]);
        } else if (Array.isArray(p._config.setupCmd) && p._config.setupCmd.length > 0) {
            Quickshell.execDetached(p._config.setupCmd);
        }
    }

    function _findById(id) {
        for (const p of providers) if (p.id === id) return p;
        return null;
    }

    function _dispatch(id, op) {
        const p = _findById(id);
        if (!p) return;
        if (p.kind === "nm") {
            // nmcli connection up/down NAME — uses the NM name as-is.
            const op2 = (op === "connect") ? "up" : "down";
            Quickshell.execDetached(["nmcli", "connection", op2, p._config.name]);
            // NM activate is fast for WireGuard, slower for OpenVPN.
            // Schedule a refresh in 1.5s so the popover updates.
            postOpRefresh.start();
        } else {
            const cmd = (op === "connect")
                      ? p._config.connectCmd
                      : p._config.disconnectCmd;
            if (Array.isArray(cmd) && cmd.length > 0) {
                Quickshell.execDetached(cmd);
                // Poll the provider's status sooner than its normal cycle.
                Qt.callLater(() => _pollCustomStatus(p._config));
            }
        }
    }

    // ---- NM source ----
    property Process _nmListProc: Process {
        id: nmListProc
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => nmListProc.collected += data + "\n"
        }
        onExited: {
            const out = [];
            // nmcli -t output: NAME:TYPE:STATE per line. NAME may
            // contain a colon — but `-t` escapes a literal `\:` so
            // splitting on bare `:` works for well-formed names. Field
            // count is exactly 3 with the -f restriction.
            for (const line of nmListProc.collected.split("\n")) {
                if (!line) continue;
                // Walk the string honouring `\:` escapes from nmcli's
                // terse output.
                const fields = _nmcliSplit(line);
                if (fields.length < 3) continue;
                const name = fields[0], type = fields[1], state = fields[2];
                if (!_isVpnType(type)) continue;
                out.push({ name, type, active: state === "activated" });
            }
            root._nmConnections = out;
        }
    }

    function _nmcliSplit(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[i + 1]; i++; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function _isVpnType(t) {
        return t === "vpn" || t === "wireguard";
    }

    function _iconForNmType(t) {
        return t === "wireguard" ? "󰖂" : "󰦝";   // wg lock / generic VPN
    }

    // ---- Custom-provider config discovery ----
    property string _customDir: Quickshell.env("HOME") + "/.config/nirimaki/vpns.d"

    property FolderListModel _customDirView: FolderListModel {
        id: customDirView
        folder: "file://" + root._customDir
        showFiles: true
        showDirs: false
        nameFilters: ["*.json"]
        sortField: FolderListModel.Name
        onCountChanged: root._scanCustomConfigs()
    }

    function _scanCustomConfigs() {
        // Spawn one cat-and-parse for each *.json. We rebuild the
        // whole list from scratch — cheap (a handful of small files
        // at most) and simpler than diffing.
        const files = [];
        for (let i = 0; i < customDirView.count; i++) {
            files.push(customDirView.get(i, "filePath"));
        }
        _loadCustomFiles(files);
    }

    function _loadCustomFiles(paths) {
        if (paths.length === 0) { _customConfigs = []; return; }
        // Use a single `cat` over all files with separators so we
        // can parse them in one shot.
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
            const out = [];
            for (let i = 0; i < loadProc.paths.length; i++) {
                const raw = chunks[i] || "";
                if (!raw.trim()) continue;
                try {
                    const cfg = JSON.parse(raw);
                    if (!cfg.id) continue;
                    out.push(cfg);
                } catch (e) {
                    console.warn("VpnService: bad json in", loadProc.paths[i], "—", e.toString());
                }
            }
            root._customConfigs = out;
            // Kick a status poll for every newly-loaded provider.
            for (const cfg of out) root._pollCustomStatus(cfg);
        }
    }

    function _shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // ---- Custom-provider status polling ----
    // Single shared Process serialises status calls. We queue (id,
    // phase) pairs — phase "status" runs statusCmd; if it parses as
    // connected, we follow up with phase "label" running
    // statusLabelCmd (when defined). Polling is driven by per-provider
    // Timers via the Repeater below.
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
        pollProc.command = cmd;
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
        // Some status commands (piactl, tailscale) exit nonzero when
        // the daemon isn't reachable; treat that as "not connected"
        // rather than warning.
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
                // If connected and a label command is configured, queue
                // it next to enrich the popover line.
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

    // Single shared poll tick for all custom providers. Per-provider
    // `pollSeconds` from the JSON is ignored in V1 — every provider
    // polls on the same 5-second cadence. Status commands are cheap
    // (piactl / tailscale status / wg show) and users typically have
    // ≤3 configured.
    property Timer _customPollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            for (const cfg of root._customConfigs) root._pollCustomStatus(cfg);
        }
    }

    // ---- Post-op refresh ----
    // After a connect/disconnect (NM specifically) we re-poll briefly
    // later so the UI catches up without waiting for the regular tick.
    property Timer _postOpRefresh: Timer {
        id: postOpRefresh
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    // ---- NM list refresh ----
    // nmcli only reflects state-change events on a re-read, so poll
    // it on the same cadence as the longest custom timer. 5s default.
    property Timer _nmTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
}
