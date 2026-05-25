pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Wrapper around Quickshell.Services.Bluetooth (BlueZ via DBus). The
// underlying module is already QML-shaped — this singleton exists to
// give plugins a stable, named entry point (parallel to AudioService /
// NotificationService / etc.), to expose pre-filtered device lists,
// and to translate BlueZ icon names into Nerd-Font glyphs.
//
//   BluetoothService.present              // adapter found at all?
//   BluetoothService.adapter              // BluetoothAdapter | null
//   BluetoothService.enabled              // bool — adapter powered
//   BluetoothService.discovering          // bool — scanning?
//   BluetoothService.discoverable         // bool — visible to others?
//   BluetoothService.devices              // [BluetoothDevice]
//   BluetoothService.connectedDevices     // [BluetoothDevice]
//   BluetoothService.pairedDevices        // [BluetoothDevice] (paired but not connected)
//   BluetoothService.availableDevices     // [BluetoothDevice] (unpaired, in range)
//
//   BluetoothService.setEnabled(bool)
//   BluetoothService.togglePower()
//   BluetoothService.setDiscovering(bool) / startScan / stopScan / toggleScan
//   BluetoothService.setDiscoverable(bool)
//   BluetoothService.connectDevice(d)
//   BluetoothService.disconnectDevice(d)
//   BluetoothService.pairDevice(d)
//   BluetoothService.cancelPair(d)
//   BluetoothService.forgetDevice(d)
//   BluetoothService.setTrusted(d, bool)
//
//   BluetoothService.displayName(d)
//   BluetoothService.deviceIcon(d)        // Nerd-Font glyph by BlueZ icon
//   BluetoothService.deviceSubtitle(d)    // status line for list rows
QtObject {
    id: root

    // ---- State ----
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: !!adapter
    readonly property string adapterName: adapter ? String(adapter.name || "") : ""
    readonly property bool enabled:       adapter ? adapter.enabled       : false
    readonly property bool discovering:   adapter ? adapter.discovering   : false
    readonly property bool discoverable:  adapter ? adapter.discoverable  : false
    readonly property int  state:         adapter ? adapter.state         : BluetoothAdapterState.Disabled
    readonly property bool busy:
        state === BluetoothAdapterState.Enabling
        || state === BluetoothAdapterState.Disabling

    // All known devices (adapter-scoped). `Bluetooth.devices` is the
    // global view across all adapters; we stick to the default adapter's
    // own list since multi-adapter rigs are rare and would otherwise
    // double-count.
    readonly property var devices:
        adapter && adapter.devices ? adapter.devices.values : []

    // Three logical buckets the panel cares about:
    //   - connected: actively talking (subset of paired)
    //   - paired:    known/bonded but currently disconnected
    //   - available: in range, not yet paired (populated by a scan)
    readonly property var connectedDevices: _filter(d => d.connected)
    readonly property var pairedDevices:
        _filter(d => d.paired && !d.connected)
    readonly property var availableDevices:
        _filter(d => !d.paired)

    // ---- Adapter API ----
    function setEnabled(b)      { if (adapter) adapter.enabled = !!b; }
    function togglePower()      { if (adapter) adapter.enabled = !adapter.enabled; }
    function setDiscovering(b)  { if (adapter) adapter.discovering = !!b; }
    function startScan()        { setDiscovering(true); }
    function stopScan()         { setDiscovering(false); }
    function toggleScan()       { setDiscovering(!discovering); }
    function setDiscoverable(b) { if (adapter) adapter.discoverable = !!b; }

    // ---- Device API ----
    function connectDevice(d)    { if (d) d.connect(); }
    function disconnectDevice(d) { if (d) d.disconnect(); }
    function pairDevice(d)       { if (d) d.pair(); }
    function cancelPair(d)       { if (d) d.cancelPair(); }
    function forgetDevice(d)     { if (d) d.forget(); }
    function setTrusted(d, b)    { if (d) d.trusted = !!b; }
    function setBlocked(d, b)    { if (d) d.blocked = !!b; }

    // Toggling connection state — single entry point for list rows.
    function toggleConnection(d) {
        if (!d) return;
        if (d.connected) d.disconnect();
        else             d.connect();
    }

    // ---- Display helpers ----
    function displayName(d) {
        if (!d) return "";
        return String(d.name || d.deviceName || d.address || "");
    }

    // BlueZ exports a freedesktop "icon" string for each device. Map
    // the common families to MDI Nerd-Font glyphs so list rows show
    // something recognizable. The fallback is the generic bluetooth
    // glyph.
    function deviceIcon(d) {
        if (!d) return "󰂲";              // nf-md-bluetooth_off
        const ic = String(d.icon || "");
        if (ic.indexOf("headset")  !== -1) return "󰋎";    // nf-md-headset
        if (ic.indexOf("headphone") !== -1
         || ic.indexOf("audio-card") !== -1
         || ic.indexOf("audio-") !== -1)   return "󰋋";    // nf-md-headphones
        if (ic.indexOf("input-keyboard") !== -1) return "󰌌"; // keyboard
        if (ic.indexOf("input-mouse")    !== -1) return "󰍽"; // mouse
        if (ic.indexOf("input-gaming")   !== -1
         || ic.indexOf("input-joystick") !== -1) return "󰊴"; // gamepad
        if (ic.indexOf("phone")    !== -1) return "󰏲";    // phone
        if (ic.indexOf("computer") !== -1) return "󰟀";    // desktop
        if (ic.indexOf("video")    !== -1) return "󰕧";    // video
        if (ic.indexOf("printer")  !== -1) return "󰐪";    // printer
        if (ic.indexOf("camera")   !== -1) return "󰄀";    // camera
        if (ic.indexOf("watch")    !== -1) return "󰖉";    // watch
        return "󰂯";                       // generic bluetooth (powered)
    }

    // Status line shown under each device row. Keep it short — most
    // value comes from "connected" vs "paired" vs the address.
    function deviceSubtitle(d) {
        if (!d) return "";
        if (d.connected) {
            if (d.batteryAvailable && d.battery > 0)
                return _connectedLabel + " · " + Math.round(d.battery * 100) + "%";
            return _connectedLabel;
        }
        if (d.pairing)         return _pairingLabel;
        if (d.paired)          return _pairedLabel;
        return String(d.address || "");
    }

    // i18n keys aren't required at construction time, so swap these
    // out as the locale becomes available. Plugins that want raw keys
    // can use `deviceState(d)` instead.
    property string _connectedLabel: "Connected"
    property string _pairedLabel:    "Paired"
    property string _pairingLabel:   "Pairing…"

    function deviceState(d) {
        if (!d) return "unknown";
        if (d.connected) return "connected";
        if (d.pairing)   return "pairing";
        if (d.paired)    return "paired";
        return "available";
    }

    // ---- Internal ----
    function _filter(pred) {
        const out = [];
        for (const d of devices) {
            try { if (pred(d)) out.push(d); }
            catch (e) {}
        }
        return out;
    }

    // IPC for diagnostics — `quickshell ipc call bluetooth dump`
    // returns a JSON snapshot of every device the adapter sees.
    property IpcHandler _ipc: IpcHandler {
        target: "bluetooth"
        function dump(): string {
            const out = [];
            for (const d of root.devices) {
                out.push({
                    address:    String(d.address || ""),
                    name:       String(d.name || d.deviceName || ""),
                    icon:       String(d.icon || ""),
                    state:      root.deviceState(d),
                    connected:  d.connected,
                    paired:     d.paired,
                    trusted:    d.trusted,
                    blocked:    d.blocked,
                    battery:    d.batteryAvailable ? d.battery : null
                });
            }
            return JSON.stringify({
                adapter: {
                    present:      root.present,
                    name:         root.adapterName,
                    enabled:      root.enabled,
                    discovering:  root.discovering,
                    discoverable: root.discoverable
                },
                devices: out
            }, null, 2);
        }
        function ping(): string { return "ok"; }
    }
}
