pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Wrapper around Quickshell.Services.Pipewire that exposes a clean
// app-facing API:
//
//   AudioService.defaultSink           // PwNode | null
//   AudioService.defaultSinkVolume     // 0..1
//   AudioService.defaultSinkMuted      // bool
//   AudioService.sinks                 // [PwNode]   — all output devices
//   AudioService.sources               // [PwNode]   — all input devices (no monitors)
//   AudioService.sinkStreams           // [PwNode]   — per-app playback streams
//   AudioService.sourceStreams         // [PwNode]   — per-app capture streams
//
//   AudioService.setDefaultSink(node)
//   AudioService.setDefaultSource(node)
//   AudioService.setVolume(node, 0..1)
//   AudioService.setMuted(node, bool)
//   AudioService.toggleMute(node)
//   AudioService.adjustDefaultSink(delta)
//
//   AudioService.displayName(node)     // description > nickname > name
//   AudioService.streamLabel(stream)   // application.name / media.name
//   AudioService.streamIcon(stream)    // Nerd-Font glyph by role
//
// Implementation note: the per-node `audio` sub-iface only emits change
// signals while a PwObjectTracker holds the node "live". We track the
// default sink/source plus every sink/source/stream we list — so the
// mixer panel can show live per-app volume changes without each plugin
// having to wire its own tracker.
QtObject {
    id: root

    // ---- Default device + state ----
    readonly property var defaultSink:   Pipewire.defaultAudioSink
    readonly property var defaultSource: Pipewire.defaultAudioSource

    readonly property real defaultSinkVolume:
        defaultSink && defaultSink.audio ? defaultSink.audio.volume : 0
    readonly property bool defaultSinkMuted:
        defaultSink && defaultSink.audio ? defaultSink.audio.muted : false
    readonly property real defaultSourceVolume:
        defaultSource && defaultSource.audio ? defaultSource.audio.volume : 0
    readonly property bool defaultSourceMuted:
        defaultSource && defaultSource.audio ? defaultSource.audio.muted : false

    // ---- Lists ----
    // `Pipewire.nodes` is a list of every PwNode; we partition it once
    // per change, exposing four typed sub-lists.
    readonly property var sinks:         _filter(_isSinkDevice)
    readonly property var sources:       _filter(_isSourceDevice)
    readonly property var sinkStreams:   _filter(_isSinkStream)
    readonly property var sourceStreams: _filter(_isSourceStream)

    // Per-process grouping for the mixer's Apps tab. Browsers like Zen
    // expose one PwNode per audio source (each tab + a master
    // "AudioStream"), all sharing `application.process.id`. The mixer
    // groups these so the user sees "Zen — 5 streams" once rather than
    // five identical-looking rows.
    readonly property var sinkStreamGroups: _groupStreams(sinkStreams)
    readonly property var sourceStreamGroups: _groupStreams(sourceStreams)

    // ---- API ----
    function setDefaultSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }
    function setDefaultSource(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }
    function setVolume(node, v) {
        if (node && node.audio)
            node.audio.volume = Math.max(0, Math.min(1, v));
    }
    function setMuted(node, m) {
        if (node && node.audio) node.audio.muted = m;
    }
    function toggleMute(node) {
        if (node && node.audio) node.audio.muted = !node.audio.muted;
    }
    function adjustDefaultSink(delta) {
        if (defaultSink && defaultSink.audio)
            setVolume(defaultSink, defaultSink.audio.volume + delta);
    }

    // ---- Display helpers ----
    function displayName(node) {
        if (!node) return "";
        return String(node.description || node.nickname || node.name || "");
    }
    function streamLabel(stream) {
        if (!stream) return "";
        const p = stream.properties || {};
        const app   = String(p["application.name"] || "");
        const media = String(p["media.name"]       || "");
        // Browsers (and most apps with multiple tabs / streams) set
        // `application.name` to the binary name and `media.name` to
        // the page title or audio source name. Surface both so users
        // can tell five "Zen" streams apart.
        if (app && media && media !== app) return app + " — " + media;
        return app || media || displayName(stream);
    }
    function streamIcon(stream) {
        const p = stream && stream.properties ? stream.properties : {};
        const role = String(p["media.role"] || p["media.class"] || "");
        if (role.indexOf("Music") !== -1) return "󰝚";
        if (role.indexOf("Video") !== -1) return "󰕧";
        if (role.indexOf("Game")  !== -1) return "󰊠";
        if (role.indexOf("Voice") !== -1) return "󰍬";
        return "󰓃";   // generic speaker
    }

    // ---- Stream group helpers (per-process aggregates) ----
    // A group is { pid, appName, icon, streams: [PwNode] }.
    function groupVolume(group) {
        if (!group || !group.streams || group.streams.length === 0) return 0;
        // Loudest stream in the group represents the group volume —
        // setting a new value writes that level to every member.
        let v = 0;
        for (const s of group.streams) {
            if (s && s.audio && s.audio.volume > v) v = s.audio.volume;
        }
        return v;
    }
    function groupMuted(group) {
        if (!group || !group.streams || group.streams.length === 0) return false;
        // The group reads as "muted" only when EVERY constituent
        // stream is muted; otherwise audio is still leaking out.
        for (const s of group.streams) {
            if (s && s.audio && !s.audio.muted) return false;
        }
        return true;
    }
    function setGroupVolume(group, v) {
        if (!group || !group.streams) return;
        for (const s of group.streams) setVolume(s, v);
    }
    function toggleGroupMute(group) {
        if (!group || !group.streams || group.streams.length === 0) return;
        const muteAll = !groupMuted(group);
        for (const s of group.streams) setMuted(s, muteAll);
    }

    function _groupStreams(streams) {
        const groups = {};
        for (const s of streams) {
            const p = s.properties || {};
            const pid = String(p["application.process.id"] || ("solo:" + s.id));
            if (!groups[pid]) {
                groups[pid] = {
                    pid:     pid,
                    appName: String(p["application.name"] || displayName(s)),
                    icon:    streamIcon(s),
                    streams: []
                };
            }
            groups[pid].streams.push(s);
        }
        return Object.values(groups);
    }

    // ---- Internal: node classification ----
    // Many Pipewire nodes don't set `media.class` (only the
    // Pulse-compatibility nodes do), but every audio node has the
    // `audio` sub-iface and the `isSink` / `isStream` flags. Classify
    // by those:
    //   - Sink device   = !isStream &&  isSink && has audio
    //   - Source device = !isStream && !isSink && has audio
    //                     (excluding monitor pseudo-sources)
    //   - Sink stream   =  isStream &&  isSink         (per-app playback)
    //   - Source stream =  isStream && !isSink         (per-app capture)
    function _isSinkDevice(n) {
        return n && n.isSink && !n.isStream && _hasAudio(n);
    }
    function _isSourceDevice(n) {
        if (!n || n.isSink || n.isStream || !_hasAudio(n)) return false;
        // Drop monitor pseudo-sources — they mirror sinks and aren't
        // what the user thinks of as "input device".
        const cls = _mediaClassOf(n);
        return cls.indexOf("Monitor") === -1;
    }
    function _isSinkStream(n) {
        return n && n.isStream && n.isSink && _hasAudio(n);
    }
    function _isSourceStream(n) {
        return n && n.isStream && !n.isSink && _hasAudio(n);
    }
    function _hasAudio(n) {
        return !!(n && n.audio);
    }
    function _mediaClassOf(n) {
        const p = n && n.properties ? n.properties : {};
        return String(p["media.class"] || "");
    }
    function _hasMediaClass(n, cls) {
        return _mediaClassOf(n) === cls;
    }

    // Debug helper — `quickshell ipc call audio dump` returns every
    // PwNode the service can see, with classification. Use to diagnose
    // why a sink/stream isn't showing up.
    function dumpNodes() {
        const out = [];
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (const n of nodes) {
            out.push({
                id:          n.id,
                name:        n.name,
                description: n.description,
                isSink:      n.isSink,
                isStream:    n.isStream,
                mediaClass:  _mediaClassOf(n),
                isSinkDev:   _isSinkDevice(n),
                isSrcDev:    _isSourceDevice(n),
                isSinkStream: _isSinkStream(n),
                isSrcStream:  _isSourceStream(n)
            });
        }
        return out;
    }

    property IpcHandler _ipc: IpcHandler {
        target: "audio"
        function dump(): string {
            return JSON.stringify(root.dumpNodes(), null, 2);
        }
        function ping(): string { return "ok"; }
    }

    function _filter(pred) {
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        const out = [];
        for (const n of nodes) {
            try { if (pred(n)) out.push(n); }
            catch (e) {}
        }
        return out;
    }

    // PwObjectTracker keeps the listed nodes live so their `audio`
    // sub-properties update reactively. Without this you can read
    // volume but you won't get notified when another app changes it.
    property PwObjectTracker _tracker: PwObjectTracker {
        objects: {
            const out = [];
            if (root.defaultSink)   out.push(root.defaultSink);
            if (root.defaultSource) out.push(root.defaultSource);
            for (const n of root.sinks)         out.push(n);
            for (const n of root.sources)       out.push(n);
            for (const n of root.sinkStreams)   out.push(n);
            for (const n of root.sourceStreams) out.push(n);
            return out;
        }
    }
}
