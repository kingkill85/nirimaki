pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wrapper around Quickshell.Networking (NetworkManager via DBus). Like
// BluetoothService, the underlying module is already QML-shaped — this
// singleton exists to give plugins a stable, named entry point and to
// expose pre-filtered/sorted views the bar + panel actually want:
//
//   NetworkService.present              // NM backend up?
//   NetworkService.wifiEnabled          // wifi radio on
//   NetworkService.wifiHardwareEnabled  // rfkill / hw kill switch
//   NetworkService.connectivity         // None/Portal/Limited/Full
//   NetworkService.devices              // [NetworkDevice]
//   NetworkService.wifiDevices          // subset of type==Wifi
//   NetworkService.wiredDevices         // subset of type==Wired
//   NetworkService.primaryDevice        // first connected device, or null
//   NetworkService.primaryNetwork       // its active Network, or null
//   NetworkService.accessPoints         // sorted unique wifi networks
//   NetworkService.scanning             // any wifi device scanning
//
//   NetworkService.setWifiEnabled(b) / toggleWifi()
//   NetworkService.startScan() / stopScan() / toggleScan()
//   NetworkService.connect(net) / connectWithPsk(net, psk)
//   NetworkService.disconnect(net) / forget(net)
//   NetworkService.disconnectDevice(dev)
//
//   NetworkService.signalBars(strength)  // 0..4 from 0..1 ratio
//   NetworkService.signalIcon(strength)  // Nerd-Font glyph
//   NetworkService.securityLabel(t)      // localised label via _wifi*Label
//   NetworkService.isSecured(net)        // true unless Open/Owe
//   NetworkService.stateLabel(s)         // localised state via _state*Label
QtObject {
    id: root

    // ---- Backend presence ----
    readonly property int backend: Networking.backend
    readonly property bool present:
        backend === NetworkBackendType.NetworkManager
    readonly property bool wifiEnabled:
        present && Networking.wifiEnabled
    readonly property bool wifiHardwareEnabled:
        present && Networking.wifiHardwareEnabled
    readonly property int  connectivity: Networking.connectivity

    // ---- Devices ----
    // `Networking.devices` is an UntypedObjectModel; iterate via .values.
    readonly property var devices:
        Networking.devices ? Networking.devices.values : []

    readonly property var wifiDevices:
        _filter(d => isWifiDevice(d))
    readonly property var wiredDevices:
        _filter(d => isWiredDevice(d))

    // Type predicates — plugins import qs only, so they can't reach the
    // DeviceType enum directly. These hide the import for them.
    function isWifiDevice(d)  { return !!d && d.type === DeviceType.Wifi; }
    function isWiredDevice(d) { return !!d && d.type === DeviceType.Wired; }

    readonly property bool primaryIsWifi:  isWifiDevice(primaryDevice)
    readonly property bool primaryIsWired: isWiredDevice(primaryDevice)

    // First connected device — used by the bar pill to decide which
    // icon to show and which network's name to display.
    readonly property var primaryDevice: {
        for (const d of devices) {
            if (d && d.connected) return d;
        }
        return null;
    }

    // Active Network on the primary device (the currently-used SSID for
    // wifi; the wired connection profile for ethernet). Reads through
    // `WiredDevice.network` when available; for wifi we scan the
    // device's networks for the connected one.
    readonly property var primaryNetwork: {
        const d = primaryDevice;
        if (!d) return null;
        if (isWiredDevice(d) && d.network) return d.network;
        if (!d.networks) return null;
        for (const n of d.networks.values || []) {
            if (n && n.connected) return n;
        }
        return null;
    }

    // ---- Wifi access points ----
    // Aggregated across every wifi device; deduplicated by name (BSSID
    // groups with same SSID are merged into one row). Sorted by
    // signalStrength desc, with connected rows pinned to the top.
    readonly property var accessPoints: _collectAccessPoints()

    readonly property bool scanning: {
        for (const d of wifiDevices) {
            if (d && d.scannerEnabled) return true;
        }
        return false;
    }

    // ---- Top-level controls ----
    function setWifiEnabled(b) {
        if (!present) return;
        Networking.wifiEnabled = !!b;
    }
    function toggleWifi() { setWifiEnabled(!wifiEnabled); }

    function setScanning(b) {
        for (const d of wifiDevices) {
            if (d) d.scannerEnabled = !!b;
        }
    }
    function startScan()  { setScanning(true); }
    function stopScan()   { setScanning(false); }
    function toggleScan() { setScanning(!scanning); }

    // ---- Network actions ----
    // Open / saved → just `connect()`. New secured networks need a
    // PSK. `forget()` removes the saved NM profile so auto-connect
    // stops happening.
    function connectNetwork(n)         { if (n) n.connect(); }
    function connectWithPsk(n, psk)    { if (n) n.connectWithPsk(String(psk || "")); }
    function disconnectNetwork(n)      { if (n) n.disconnect(); }
    function forgetNetwork(n)          { if (n) n.forget(); }
    function disconnectDevice(d)       { if (d) d.disconnect(); }
    function setAutoconnect(d, b)      { if (d) d.autoconnect = !!b; }

    // ---- Display helpers ----
    // Bars: 0..4, mapped from the 0..1 ratio NetworkManager returns.
    // Anything below 12 % counts as 1 bar so we never show 0 next to
    // a still-listed AP.
    function signalBars(strength) {
        const s = Number(strength) || 0;
        if (s >= 0.80) return 4;
        if (s >= 0.55) return 3;
        if (s >= 0.30) return 2;
        return 1;
    }

    function signalIcon(strength) {
        const b = signalBars(strength);
        if (b >= 4) return "󰤨";   // nf-md-wifi_strength_4
        if (b >= 3) return "󰤥";   // 3
        if (b >= 2) return "󰤢";   // 2
        return "󰤟";              // 1
    }

    function isSecured(n) {
        if (!n || n.security === undefined) return false;
        const t = n.security;
        return t !== WifiSecurityType.Open && t !== WifiSecurityType.Unknown;
    }

    function securityLabel(t) {
        switch (t) {
        case WifiSecurityType.Open:           return _wifiOpenLabel;
        case WifiSecurityType.Owe:            return "OWE";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:     return "WEP";
        case WifiSecurityType.WpaPsk:         return "WPA";
        case WifiSecurityType.Wpa2Psk:        return "WPA2";
        case WifiSecurityType.WpaEap:         return "WPA-EAP";
        case WifiSecurityType.Wpa2Eap:        return "WPA2-EAP";
        case WifiSecurityType.Sae:            return "WPA3";
        case WifiSecurityType.Wpa3SuiteB192:  return "WPA3-192";
        case WifiSecurityType.Leap:           return "LEAP";
        }
        return "";
    }

    function stateLabel(s) {
        switch (s) {
        case ConnectionState.Connected:     return _stateConnectedLabel;
        case ConnectionState.Connecting:    return _stateConnectingLabel;
        case ConnectionState.Disconnecting: return _stateDisconnectingLabel;
        case ConnectionState.Disconnected:  return _stateDisconnectedLabel;
        }
        return "";
    }

    // Connectivity labels for status text — "Limited"/"Portal" both
    // imply the link is up but Internet probes failed.
    function connectivityLabel() {
        switch (connectivity) {
        case NetworkConnectivity.Full:    return _connectivityFullLabel;
        case NetworkConnectivity.Portal:  return _connectivityPortalLabel;
        case NetworkConnectivity.Limited: return _connectivityLimitedLabel;
        case NetworkConnectivity.None:    return _connectivityNoneLabel;
        }
        return "";
    }

    // i18n labels — kept on the service so plugins don't need to
    // localise enum values themselves. Panel writes these at construction
    // + on locale change (mirrors BluetoothService's pattern).
    property string _wifiOpenLabel:            "Open"
    property string _stateConnectedLabel:      "Connected"
    property string _stateConnectingLabel:     "Connecting…"
    property string _stateDisconnectingLabel:  "Disconnecting…"
    property string _stateDisconnectedLabel:   "Disconnected"
    property string _connectivityFullLabel:    "Online"
    property string _connectivityPortalLabel:  "Captive portal"
    property string _connectivityLimitedLabel: "Limited"
    property string _connectivityNoneLabel:    "Offline"

    // ---- Internal ----
    function _filter(pred) {
        const out = [];
        for (const d of devices) {
            try { if (pred(d)) out.push(d); }
            catch (e) {}
        }
        return out;
    }

    // Walk every wifi device's `networks` model, dedupe by SSID
    // (keeping the strongest signal per SSID), then sort:
    //   1. connected first
    //   2. known (saved profile) next
    //   3. signal strength desc
    function _collectAccessPoints() {
        const byName = ({});
        for (const dev of wifiDevices) {
            if (!dev || !dev.networks) continue;
            for (const n of dev.networks.values || []) {
                if (!n) continue;
                const name = String(n.name || "");
                if (!name) continue;
                const existing = byName[name];
                if (!existing) {
                    byName[name] = n;
                } else {
                    // Connected always wins; otherwise pick the stronger.
                    if (n.connected && !existing.connected) byName[name] = n;
                    else if (!existing.connected
                             && (n.signalStrength || 0) > (existing.signalStrength || 0))
                        byName[name] = n;
                }
            }
        }
        const arr = Object.values(byName);
        arr.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known)         return a.known ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return arr;
    }

    // IPC for diagnostics — `quickshell ipc call network dump` returns
    // a JSON snapshot of every device + access point.
    property IpcHandler _ipc: IpcHandler {
        target: "network"

        function dump(): string {
            const devs = [];
            for (const d of root.devices) {
                devs.push({
                    type:        d.type === DeviceType.Wifi ? "wifi"
                                : d.type === DeviceType.Wired ? "wired" : "other",
                    name:        String(d.name || ""),
                    address:     String(d.address || ""),
                    connected:   d.connected,
                    state:       root.stateLabel(d.state),
                    autoconnect: d.autoconnect,
                    nmManaged:   d.nmManaged,
                    linkSpeed:   d.linkSpeed || null,
                    hasLink:     d.hasLink === undefined ? null : d.hasLink,
                    scanning:    d.scannerEnabled === undefined ? null : d.scannerEnabled
                });
            }
            const aps = [];
            for (const n of root.accessPoints) {
                aps.push({
                    name:       String(n.name || ""),
                    signal:     n.signalStrength,
                    bars:       root.signalBars(n.signalStrength),
                    security:   root.securityLabel(n.security),
                    known:      n.known,
                    connected:  n.connected,
                    state:      root.stateLabel(n.state)
                });
            }
            return JSON.stringify({
                backend:       backend === NetworkBackendType.NetworkManager ? "nm" : "none",
                wifiEnabled:   root.wifiEnabled,
                wifiHwEnabled: root.wifiHardwareEnabled,
                connectivity:  root.connectivityLabel(),
                scanning:      root.scanning,
                devices:       devs,
                accessPoints:  aps
            }, null, 2);
        }

        function scan(): string {
            root.toggleScan();
            return root.scanning ? "scanning" : "stopped";
        }

        function ping(): string { return "ok"; }
    }
}
