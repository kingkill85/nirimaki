import QtQuick
import qs

// Full network manager — lazy-summoned overlay.
//
//   quickshell ipc call shell summon network
//
// Two tabs:
//   1. WI-FI    SSID list with connect / disconnect / forget actions,
//               PSK prompt for unknown secured networks, scan toggle.
//   2. WIRED    Per-interface state, link speed, IP/gateway/connectivity.
//
// Reads/writes state via NetworkService, which wraps
// Quickshell.Networking (NetworkManager via DBus). Two tabs mirror the
// audio + bluetooth panels so service-panel behaviour is uniform.
DialogShell {
    id: shell
    open: true
    cardWidth: 560
    cardHeight: 600
    dialogNamespace: "nirimaki-network-panel"

    onCloseRequested: Plugins.hide("network")

    // 0 = wifi, 1 = wired
    property int currentTab: NetworkService.wifiDevices.length > 0 ? 0 : 1

    // Network currently in the PSK-entry flow (null = no prompt).
    property var pskTarget: null

    // Localised enum labels for NetworkService. Service stays free of
    // I18n; panel feeds it the strings on construction + locale change.
    Connections {
        target: I18n
        function onLocaleChanged() { shell._refreshLabels(); }
    }
    Component.onCompleted: shell._refreshLabels()
    function _refreshLabels() {
        NetworkService._wifiOpenLabel            = I18n.t("network.security.open");
        NetworkService._stateConnectedLabel      = I18n.t("network.state.connected");
        NetworkService._stateConnectingLabel    = I18n.t("network.state.connecting");
        NetworkService._stateDisconnectingLabel = I18n.t("network.state.disconnecting");
        NetworkService._stateDisconnectedLabel  = I18n.t("network.state.disconnected");
        NetworkService._connectivityFullLabel    = I18n.t("network.connectivity.full");
        NetworkService._connectivityPortalLabel  = I18n.t("network.connectivity.portal");
        NetworkService._connectivityLimitedLabel = I18n.t("network.connectivity.limited");
        NetworkService._connectivityNoneLabel    = I18n.t("network.connectivity.none");
    }

    Item {
        width: 0; height: 0
        focus: true
        Keys.onEscapePressed: {
            if (shell.pskTarget) shell.pskTarget = null;
            else                 Plugins.hide("network");
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18

        // ---- Header ----
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12
            height: 40

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: NetworkService.primaryIsWifi
                          ? NetworkService.signalIcon(
                                NetworkService.primaryNetwork
                                    ? NetworkService.primaryNetwork.signalStrength
                                    : 0)
                      : NetworkService.primaryIsWired ? "󰈀"
                      : (NetworkService.wifiEnabled ? "󰤯" : "󰖪")
                color: NetworkService.primaryDevice
                       && NetworkService.primaryDevice.connected
                          ? Theme.fg : Theme.fgDim
                font.family: Theme.iconFamily
                font.pixelSize: Theme.fontPxLarge + 4
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: parent.width - 80 - parent.spacing * 2 - 28

                Text {
                    text: I18n.t("network.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                }
                Text {
                    text: NetworkService.connectivityLabel()
                          + (NetworkService.primaryNetwork
                                && NetworkService.primaryNetwork.name
                              ? "  ·  " + NetworkService.primaryNetwork.name
                              : "")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.t("network.close")
                onTriggered: Plugins.hide("network")
            }
        }

        // ---- Tab bar ----
        TabBar {
            id: tabs
            anchors.top: header.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            tabs: [
                I18n.t("network.tab.wifi"),
                I18n.t("network.tab.wired")
            ]
            currentIndex: shell.currentTab
            onTabClicked: (i) => shell.currentTab = i
        }

        // ---- Tab content ----
        Item {
            anchors.top: tabs.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // ---------------- WI-FI tab ----------------
            Item {
                visible: shell.currentTab === 0
                anchors.fill: parent

                // No NM backend at all.
                Text {
                    anchors.centerIn: parent
                    visible: !NetworkService.present
                    width: 360
                    text: I18n.t("network.no_backend")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                // No wifi device on the system.
                Text {
                    anchors.centerIn: parent
                    visible: NetworkService.present
                             && NetworkService.wifiDevices.length === 0
                    width: 360
                    text: I18n.t("network.no_wifi")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                // Wifi present but radio off — large icon + helper +
                // turn-on button. Mirrors bluetooth's "adapter off" state.
                Column {
                    anchors.centerIn: parent
                    visible: NetworkService.present
                             && NetworkService.wifiDevices.length > 0
                             && !NetworkService.wifiEnabled
                    spacing: 12
                    width: 320

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰖪"   // wifi-strength-off-outline
                        color: Theme.fgDim
                        font.family: Theme.iconFamily
                        font.pixelSize: Theme.fontPxLarge + 12
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: NetworkService.wifiHardwareEnabled
                              ? I18n.t("network.empty_wifi_off")
                              : I18n.t("network.empty_wifi_rfkill")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: NetworkService.wifiHardwareEnabled
                        label: I18n.t("network.wifi_on")
                        variant: Button.Primary
                        onTriggered: NetworkService.setWifiEnabled(true)
                    }
                }

                // Active list — Flickable (not ScrollView, gotcha 5).
                Flickable {
                    id: wifiFlick
                    visible: NetworkService.present
                             && NetworkService.wifiDevices.length > 0
                             && NetworkService.wifiEnabled
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: wifiCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: wifiCol
                        width: wifiFlick.width
                        spacing: 12

                        // ---- Section header with wifi toggle + scan button.
                        Item {
                            width: parent.width
                            height: Theme.controlHeight

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t("network.section.networks")
                                color: Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 2
                                font.bold: true
                                font.letterSpacing: 2
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Button {
                                    label: NetworkService.scanning
                                              ? I18n.t("network.scan_stop")
                                              : I18n.t("network.scan_start")
                                    variant: NetworkService.scanning
                                                ? Button.Urgent
                                                : Button.Secondary
                                    onTriggered: NetworkService.toggleScan()
                                }
                                Button {
                                    label: I18n.t("network.wifi_off")
                                    variant: Button.Secondary
                                    onTriggered: NetworkService.setWifiEnabled(false)
                                }
                            }
                        }

                        // ---- Access points
                        Repeater {
                            model: NetworkService.accessPoints
                            delegate: wifiRow
                        }

                        Text {
                            visible: NetworkService.accessPoints.length === 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: NetworkService.scanning
                                  ? I18n.t("network.scanning")
                                  : I18n.t("network.empty_aps")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            font.italic: true
                        }
                    }
                }
            }

            // ---------------- WIRED tab ----------------
            Item {
                visible: shell.currentTab === 1
                anchors.fill: parent

                Text {
                    anchors.centerIn: parent
                    visible: NetworkService.wiredDevices.length === 0
                    text: I18n.t("network.no_wired")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.italic: true
                }

                Column {
                    visible: NetworkService.wiredDevices.length > 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 12

                    Text {
                        text: I18n.t("network.section.interfaces")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Repeater {
                        model: NetworkService.wiredDevices
                        delegate: wiredRow
                    }
                }
            }
        }
    }

    // ---- Wifi-row component ----
    // Re-used for every AP. Contextually shows: Disconnect on the
    // connected row; Connect+Forget on known rows; Connect on open
    // unknowns; "Enter password" → PSK prompt on secured unknowns.
    Component {
        id: wifiRow

        Rectangle {
            id: row
            required property var modelData
            readonly property var net: row.modelData
            readonly property bool secured: NetworkService.isSecured(net)
            readonly property bool busy:    net && net.stateChanging
            readonly property bool isPskTarget: shell.pskTarget === net

            width: parent ? parent.width : 0
            height: (isPskTarget ? pskCol.implicitHeight : rowBody.implicitHeight) + 16
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
                           net && net.connected ? 0.07 : 0.04)
            Behavior on height { NumberAnimation { duration: 100 } }

            // Subtitle: state when connected, "Saved · WPA2" when known,
            // bare security otherwise. Busy suffix appended for in-flight
            // connects. Built in JS to skip trailing separators cleanly.
            function _subtitle() {
                if (!net) return "";
                if (net.connected) return NetworkService.stateLabel(net.state);
                const parts = [];
                if (net.known) parts.push(I18n.t("network.row.saved"));
                const sec = NetworkService.securityLabel(net.security);
                if (sec) parts.push(sec);
                if (busy) parts.push(NetworkService.stateLabel(net.state));
                return parts.join("  ·  ");
            }

            // ---- Main row (icon + name + actions) ----
            Row {
                id: rowBody
                visible: !row.isPskTarget
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: NetworkService.signalIcon(row.net ? row.net.signalStrength : 0)
                    color: row.net && row.net.connected ? Theme.accent : Theme.fg
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.iconPx + 2
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - actions.implicitWidth - 2 * parent.spacing
                    spacing: 2

                    Row {
                        spacing: 6
                        width: parent.width

                        Text {
                            text: row.net ? String(row.net.name || "") : "—"
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            elide: Text.ElideRight
                            width: parent.width - 24
                        }
                        Text {
                            visible: row.secured
                            text: "󰌾"
                            color: Theme.fgDim
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.iconPx - 4
                        }
                    }
                    Text {
                        text: row._subtitle()
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
                Row {
                    id: actions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Connected → Disconnect.
                    Button {
                        visible: row.net && row.net.connected
                        label: I18n.t("network.action.disconnect")
                        variant: Button.Urgent
                        onTriggered: NetworkService.disconnectNetwork(row.net)
                    }
                    // Known but disconnected → Connect + Forget.
                    Button {
                        visible: row.net && row.net.known && !row.net.connected
                        label: I18n.t("network.action.connect")
                        variant: Button.Primary
                        enabled: !row.busy
                        onTriggered: NetworkService.connectNetwork(row.net)
                    }
                    Button {
                        visible: row.net && row.net.known && !row.net.connected
                        label: I18n.t("network.action.forget")
                        variant: Button.Secondary
                        onTriggered: NetworkService.forgetNetwork(row.net)
                    }
                    // Unknown open → direct Connect.
                    Button {
                        visible: row.net && !row.net.known && !row.secured
                        label: I18n.t("network.action.connect")
                        variant: Button.Primary
                        enabled: !row.busy
                        onTriggered: NetworkService.connectNetwork(row.net)
                    }
                    // Unknown secured → expand into PSK prompt.
                    Button {
                        visible: row.net && !row.net.known && row.secured
                        label: I18n.t("network.action.password")
                        variant: Button.Primary
                        enabled: !row.busy
                        onTriggered: shell.pskTarget = row.net
                    }
                }
            }

            // ---- PSK prompt (replaces main row when active) ----
            Column {
                id: pskCol
                visible: row.isPskTarget
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: I18n.t("network.psk.title").replace("{0}",
                              row.net ? String(row.net.name || "") : "")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }
                TextField {
                    id: pskField
                    width: parent.width
                    placeholder: I18n.t("network.psk.placeholder")
                    echoMode: TextInput.Password
                    onAccepted: (t) => pskConnect.trigger()
                }
                Row {
                    spacing: 6
                    anchors.right: parent.right

                    Button {
                        id: pskCancel
                        label: I18n.t("network.psk.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.pskTarget = null
                    }
                    Button {
                        id: pskConnect
                        label: I18n.t("network.psk.connect")
                        variant: Button.Primary
                        enabled: pskField.text.length >= 8
                        function trigger() {
                            if (!enabled) return;
                            NetworkService.connectWithPsk(row.net, pskField.text);
                            shell.pskTarget = null;
                        }
                        onTriggered: trigger()
                    }
                }
            }
        }
    }

    // ---- Wired-row component ----
    // Per-interface card: name + state + linkSpeed + autoconnect toggle
    // + disconnect button. Most users have one wired interface — this
    // mirrors what `ip` would tell them at a glance.
    Component {
        id: wiredRow

        Rectangle {
            id: row
            required property var modelData
            readonly property var dev: row.modelData

            width: parent ? parent.width : 0
            height: rowBody.implicitHeight + 16
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: rowBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 12
                spacing: 6

                Row {
                    spacing: 10
                    width: parent.width

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰈀"
                        color: row.dev && row.dev.connected ? Theme.accent : Theme.fgDim
                        font.family: Theme.iconFamily
                        font.pixelSize: Theme.iconPx + 2
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 - wiredActions.implicitWidth - 2 * parent.spacing
                        spacing: 2

                        Text {
                            text: row.dev ? String(row.dev.name || "—") : "—"
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: {
                                if (!row.dev) return "";
                                const parts = [];
                                const st = NetworkService.stateLabel(row.dev.state);
                                if (st) parts.push(st);
                                if (row.dev.linkSpeed > 0)
                                    parts.push(row.dev.linkSpeed + " Mbps");
                                if (row.dev.address)
                                    parts.push(String(row.dev.address));
                                return parts.join("  ·  ");
                            }
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 3
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                    Row {
                        id: wiredActions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Button {
                            visible: row.dev && row.dev.connected
                            label: I18n.t("network.action.disconnect")
                            variant: Button.Urgent
                            onTriggered: NetworkService.disconnectDevice(row.dev)
                        }
                        // Reconnect via the device's saved Network profile.
                        // NM keeps `device.network` pointing at the most-
                        // recent profile after a manual disconnect, so this
                        // re-activates it without rebuilding settings.
                        Button {
                            visible: row.dev && !row.dev.connected && row.dev.network
                            enabled: row.dev && row.dev.network && !row.dev.network.stateChanging
                            label: I18n.t("network.action.connect")
                            variant: Button.Primary
                            onTriggered: NetworkService.connectNetwork(row.dev.network)
                        }
                    }
                }

                Toggle {
                    width: parent.width
                    label: I18n.t("network.toggle.autoconnect")
                    checked: row.dev ? row.dev.autoconnect : false
                    onToggled: (v) => NetworkService.setAutoconnect(row.dev, v)
                }
            }
        }
    }
}
