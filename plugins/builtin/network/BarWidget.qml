import QtQuick
import Quickshell.Io
import qs

// Network bar widget. State comes from NetworkService — no more
// `ip route` + /sys/class/net polling.
//   Left click   → compact popover (status, top 3 wifi APs, open panel)
//   Right click  → summon the full network panel
//   The icon mirrors the primary connection: signal bars for wifi,
//   ethernet glyph for wired, "disconnected" otherwise.
//
// The popover *does* run a one-shot `nmcli device show <iface>` on
// open to fetch live IP / gateway / DNS — Quickshell.Networking only
// exposes hardware fields, not the assigned IPv4 layer.
Item {
    id: root

    property var barWindow: null

    readonly property var device:        NetworkService.primaryDevice
    readonly property var network:       NetworkService.primaryNetwork
    readonly property bool isWifi:       NetworkService.isWifiDevice(device)
    readonly property bool isWired:      NetworkService.isWiredDevice(device)
    readonly property bool connected:    !!device && device.connected
    readonly property real signalStrength: network && network.signalStrength !== undefined
                                           ? network.signalStrength : 0
    readonly property string ssid:       network ? String(network.name || "") : ""
    readonly property string ifname:     device  ? String(device.name  || "") : ""

    // Live IPv4 layer for the primary device. Refreshed on popover open
    // (and any time `ifname` changes while the popover is showing).
    property var info: ({})   // { ip4, gateway, dns[], speed }

    // Live throughput for the primary iface, sampled while the popover is
    // open. Quickshell.Networking / NetworkService expose no byte counters,
    // so read /sys/class/net/<if>/statistics directly and diff per tick.
    property real rxRate: 0       // bytes/sec
    property real txRate: 0
    property real _prevRx: -1     // <0 = no baseline yet (first sample)
    property real _prevTx: -1
    readonly property int rateIntervalMs: 2000

    function _resetRates() {
        root._prevRx = -1; root._prevTx = -1;
        root.rxRate = 0; root.txRate = 0;
    }

    // Human-readable transfer rate: B/s → KB/s → MB/s → GB/s.
    function fmtRate(bps) {
        if (!bps || bps < 1) return "0 B/s";
        const u = ["B/s", "KB/s", "MB/s", "GB/s"];
        let i = 0, v = bps;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (i === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    function _sampleRate() {
        const name = root.ifname;
        if (!name) { root._resetRates(); return; }
        rateProc.command = ["cat",
            "/sys/class/net/" + name + "/statistics/rx_bytes",
            "/sys/class/net/" + name + "/statistics/tx_bytes"];
        rateProc.running = true;
    }

    Process {
        id: rateProc
        stdout: StdioCollector {
            id: rateOut
            waitForEnd: true
            onStreamFinished: {
                const nums = String(rateOut.text || "").trim().split(/\s+/);
                if (nums.length < 2) return;
                const rx = parseInt(nums[0]) || 0;
                const tx = parseInt(nums[1]) || 0;
                // First sample only sets the baseline (rate stays 0); a real
                // rate appears on the next tick from the byte delta.
                if (root._prevRx >= 0) {
                    const dt = root.rateIntervalMs / 1000;
                    root.rxRate = Math.max(0, (rx - root._prevRx) / dt);
                    root.txRate = Math.max(0, (tx - root._prevTx) / dt);
                }
                root._prevRx = rx;
                root._prevTx = tx;
            }
        }
    }

    Timer {
        interval: root.rateIntervalMs
        running:  popover.popupOpen && root.connected
        repeat:   true
        triggeredOnStart: true   // grab the baseline the moment it opens
        onTriggered: root._sampleRate()
    }

    function _refreshInfo() {
        const name = root.ifname;
        if (!name) { root.info = ({}); return; }
        infoProc.command = ["nmcli", "-t", "-e", "no", "-f",
                            "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,GENERAL.DEVICE",
                            "device", "show", name];
        infoProc.running = true;
    }

    Process {
        id: infoProc
        stdout: StdioCollector {
            id: infoOut
            waitForEnd: true
            onStreamFinished: {
                const next = { dns: [] };
                for (const line of String(infoOut.text || "").split("\n")) {
                    if (!line) continue;
                    const idx = line.indexOf(":");
                    if (idx === -1) continue;
                    const key = line.substring(0, idx);
                    const val = line.substring(idx + 1).trim();
                    if (!val || val === "--") continue;
                    if (key.startsWith("IP4.ADDRESS"))        next.ip4 = val;
                    else if (key.startsWith("IP4.GATEWAY"))   next.gateway = val;
                    else if (key.startsWith("IP4.DNS"))       next.dns.push(val);
                }
                root.info = next;
            }
        }
    }

    readonly property string icon:
        !NetworkService.present ? "󰤭"                 // wifi-strength-off (no backend)
        : isWifi
            ? (connected ? NetworkService.signalIcon(signalStrength)
                         : (NetworkService.wifiEnabled ? "󰤯" : "󰖪"))   // wifi-off / wifi-strength-outline
        : isWired
            ? "󰈀"                                     // ethernet
        : (NetworkService.wifiEnabled ? "󰤯" : "󰖪")    // disconnected — wifi state hint

    readonly property color iconColor:
        connected ? Theme.fg : Theme.fgDim

    function openPanel() {
        popover.close();
        Plugins.summon("network");
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        tooltipText: !NetworkService.present
            ? I18n.t("network.tooltip_nobackend")
            : root.connected
                ? (root.isWifi
                    ? I18n.t("network.tooltip_wifi")
                          .replace("{0}", root.ssid)
                          .replace("{1}", Math.round(root.signalStrength * 100))
                    : I18n.t("network.tooltip_wired"))
                : (NetworkService.wifiEnabled
                    ? I18n.t("network.tooltip_disconnected")
                    : I18n.t("network.tooltip_wifi_off"))
        onClicked:      popover.toggle()
        onRightClicked: root.openPanel()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.iconColor
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    // ---------------- Popup ----------------
    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        // Re-query IP/gateway/DNS each time the popover opens, and
        // any time the active interface changes while it's showing.
        onPopupOpenChanged: if (popupOpen) { root._resetRates(); root._refreshInfo(); }
        Connections {
            target: root
            function onIfnameChanged() {
                if (popover.popupOpen) { root._resetRates(); root._refreshInfo(); }
            }
        }

        implicitWidth:  320
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            // Top 3 visible-but-unconnected access points. Cheap
            // quick-glance surface so users can see neighbours without
            // opening the panel. Hidden when wifi is off.
            property var _topAps: {
                if (!NetworkService.wifiEnabled) return [];
                const out = [];
                for (const n of NetworkService.accessPoints) {
                    if (n.connected) continue;
                    out.push(n);
                    if (out.length >= 3) break;
                }
                return out;
            }

            PopoverHeader {
                icon:      root.icon
                iconColor: root.iconColor
                title:     root.connected
                              ? (root.ssid || I18n.t("network.ethernet"))
                              : I18n.t("network.disconnected")
                subtitle:  root.connected
                              ? (root.isWifi
                                  ? Math.round(root.signalStrength * 100) + "%  ·  "
                                    + NetworkService.connectivityLabel()
                                  : NetworkService.connectivityLabel())
                              : (NetworkService.wifiEnabled
                                  ? I18n.t("network.scan_or_pick")
                                  : I18n.t("network.wifi_is_off"))
            }

            PopoverDivider { visible: root.connected }

            // Connection details. Two-column key/value grid — only the
            // rows with data render, so an interface with no DNS just
            // omits that row instead of showing "—".
            Grid {
                visible: root.connected
                columns: 2
                columnSpacing: 14
                rowSpacing: 4
                width: parent.width

                // Interface (always — useful on multi-NIC boxes).
                Text { text: I18n.t("network.iface"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { text: root.ifname || "—"; color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2 }

                // Security (wifi only)
                Text { visible: root.isWifi && root.network
                       text: I18n.t("network.security"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { visible: root.isWifi && root.network
                       text: NetworkService.securityLabel(root.network ? root.network.security : 0) || "—"
                       color: Theme.fg
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }

                // Link speed (wired only — wifi rates are advisory)
                Text { visible: root.isWired && root.device && root.device.linkSpeed > 0
                       text: I18n.t("network.link"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { visible: root.isWired && root.device && root.device.linkSpeed > 0
                       text: (root.device ? root.device.linkSpeed : 0) + " Mbps"
                       color: Theme.fg
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }

                // IPv4 address
                Text { visible: !!root.info.ip4
                       text: I18n.t("network.ip"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { visible: !!root.info.ip4
                       text: root.info.ip4 || ""; color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2 }

                // Gateway
                Text { visible: !!root.info.gateway
                       text: I18n.t("network.gateway"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { visible: !!root.info.gateway
                       text: root.info.gateway || ""; color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2 }

                // DNS — comma-joined; ElideRight on the value cell so
                // long DNS lists don't blow up the popover width.
                Text { visible: !!(root.info.dns && root.info.dns.length > 0)
                       text: I18n.t("network.dns"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { visible: !!(root.info.dns && root.info.dns.length > 0)
                       text: (root.info.dns || []).join(", "); color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2
                       elide: Text.ElideRight
                       width: 200 }

                // Live throughput — updated every rateIntervalMs while open.
                Text { text: I18n.t("network.down"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { text: "󰇚  " + root.fmtRate(root.rxRate); color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2 }

                Text { text: I18n.t("network.up"); color: Theme.fgDim
                       font.family: Theme.sansFamily
                       font.pixelSize: Theme.fontPx - 2 }
                Text { text: "󰕒  " + root.fmtRate(root.txRate); color: Theme.fg
                       font.family: Theme.monoFamily
                       font.pixelSize: Theme.fontPx - 2 }
            }

            PopoverDivider { visible: root.connected && card._topAps.length > 0 }

            Column {
                visible: NetworkService.wifiEnabled && card._topAps.length > 0
                width: parent.width
                spacing: 4

                Repeater {
                    model: card._topAps
                    delegate: Row {
                        required property var modelData
                        readonly property var net: modelData
                        width: parent.width
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NetworkService.signalIcon(parent.net.signalStrength)
                            color: parent.net.known ? Theme.fg : Theme.fgDim
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.iconPx - 2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - 36
                            text: String(parent.net.name || "")
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: NetworkService.isSecured(parent.net)
                            text: "󰌾"   // nf-md-lock
                            color: Theme.fgDim
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.iconPx - 4
                        }
                    }
                }
            }

            PopoverDivider { visible: NetworkService.wifiEnabled && card._topAps.length > 0 }

            PopoverActions {
                PopoverButton {
                    visible: root.isWifi || (!root.connected && NetworkService.wifiDevices.length > 0)
                    label: NetworkService.wifiEnabled
                              ? I18n.t("network.wifi_off")
                              : I18n.t("network.wifi_on")
                    variant: NetworkService.wifiEnabled
                                ? PopoverButton.Secondary
                                : PopoverButton.Primary
                    onTriggered: NetworkService.toggleWifi()
                }
                PopoverButton {
                    label: I18n.t("network.bar.panel")
                    variant: PopoverButton.Primary
                    onTriggered: root.openPanel()
                }
            }
        }
    }
}
