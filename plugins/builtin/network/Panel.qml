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

    // 0 = wifi, 1 = wired, 2 = vpn
    property int currentTab: NetworkService.wifiDevices.length > 0 ? 0 : 1

    // Network currently in the PSK-entry flow (null = no prompt).
    property var pskTarget: null

    // Refresh i18n labels on construction. Tab deep-link handled below
    // via a payload watcher so re-summon (panel already alive) also
    // honours the focus hint.
    Component.onCompleted: {
        shell._refreshLabels();
        shell._applySummonPayload();
    }

    // Re-summon while the panel is already alive doesn't re-fire
    // Component.onCompleted — it only flips summonPayload["network"].
    // Watch for that change and apply the focus hint each time.
    Connections {
        target: Plugins
        function onSummonPayloadChanged() { shell._applySummonPayload(); }
    }
    function _applySummonPayload() {
        const p = Plugins.summonPayload["network"];
        if (!p) return;
        if (p.focus === "vpn")   shell.currentTab = 2;
        if (p.focus === "wifi")  shell.currentTab = 0;
        if (p.focus === "wired") shell.currentTab = 1;
    }

    // Provider whose fields[] editor is currently expanded inline. id
    // string when expanded, "" when collapsed. One-at-a-time keeps the
    // panel tidy.
    property string vpnEditing: ""

    // Provider currently in the "remove this connection?" confirmation
    // flow. id when prompting, "" otherwise. Mutually exclusive with
    // vpnEditing (clicking Remove auto-closes the editor).
    property string vpnConfirmRemove: ""

    // Provider id chosen in the Add dropdown — empty when idle, set
    // when a provider's inline Add form is visible. Each form has its
    // own Cancel that clears this back to "".
    property string vpnAddingProvider: ""

    // Localised enum labels for NetworkService. Service stays free of
    // I18n; panel feeds it the strings on construction + locale change.
    Connections {
        target: I18n
        function onLocaleChanged() { shell._refreshLabels(); }
    }
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
                I18n.t("network.tab.wired"),
                I18n.t("network.tab.vpn")
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

                // Active list — Flickable so many adapters scroll (gotcha 5).
                Flickable {
                    id: wiredFlick
                    visible: NetworkService.wiredDevices.length > 0
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: wiredCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: wiredCol
                        width: wiredFlick.width
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

            // ---------------- VPN tab ----------------
            // Two regions:
            //   1. CONNECTIONS — one row per active vpns.d/*.json and
            //      NM VPN profile. Each row has Connect/Disconnect,
            //      Configure (fields editor), Remove (with confirm).
            //   2. ADD CONNECTION — single dropdown listing every
            //      installed-package provider that's eligible. Picking
            //      a single-instance one (tailscale/pia/netextender)
            //      registers immediately. Picking a multi-instance
            //      one (wg/openvpn) opens a name-prompt row first.
            //
            // Install / Remove of the underlying *package* lives in
            // Settings Menu → Install / Remove → Service.
            Item {
                visible: shell.currentTab === 2
                anchors.fill: parent

                Flickable {
                    id: vpnFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: vpnCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: vpnCol
                        width: vpnFlick.width
                        spacing: 12

                        // ---- Empty state ----
                        // Show when nothing is registered AND nothing is
                        // installed. If a package is installed but no
                        // connection exists, the Add row below carries
                        // the user forward.
                        Text {
                            visible: VpnService.providers.length === 0
                                     && VpnService.addableProviders.length === 0
                            width: parent.width
                            text: I18n.t("network.vpn.empty_no_packages")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            font.italic: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            visible: VpnService.providers.length === 0
                                     && VpnService.addableProviders.length > 0
                            width: parent.width
                            text: I18n.t("network.vpn.empty")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            font.italic: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // ---- Section header: CONNECTIONS ----
                        Item {
                            visible: VpnService.providers.length > 0
                            width: parent.width
                            height: Theme.controlHeight

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t("network.vpn.section.active")
                                color: Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 2
                                font.bold: true
                                font.letterSpacing: 2
                            }
                        }
                        Repeater {
                            model: VpnService.providers
                            delegate: vpnRow
                        }

                        // ---- Section header: ADD CONNECTION ----
                        Item {
                            visible: VpnService.addableProviders.length > 0
                            width: parent.width
                            height: Theme.controlHeight

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t("network.vpn.section.add")
                                color: Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 2
                                font.bold: true
                                font.letterSpacing: 2
                            }
                        }

                        // ---- Add row: dropdown + button (idle state) ----
                        // Click Add → vpnAddingProvider becomes the picked
                        // id, the inline form below expands with provider-
                        // specific fields.
                        Rectangle {
                            visible: VpnService.addableProviders.length > 0
                                     && shell.vpnAddingProvider === ""
                            width: parent.width
                            height: addRow.implicitHeight + 16
                            radius: Theme.radius
                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

                            Row {
                                id: addRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                spacing: 10

                                Dropdown {
                                    id: addDropdown
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - addButton.implicitWidth - parent.spacing
                                    model: VpnService.addableProviders
                                    textRole: "name"
                                    valueRole: "id"
                                    placeholder: I18n.t("network.vpn.add_placeholder")
                                }
                                Button {
                                    id: addButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: I18n.t("network.vpn.add_action")
                                    variant: Button.Primary
                                    enabled: addDropdown.currentIndex >= 0
                                    onTriggered: {
                                        if (addDropdown.currentIndex < 0) return;
                                        const item = addDropdown.currentItem;
                                        if (!item) return;
                                        shell.vpnAddingProvider = item.id;
                                    }
                                }
                            }
                        }

                        // ---- Provider-specific Add forms ----
                        // One Loader, sourceComponent flips based on which
                        // provider was picked. Sign-in providers (tailscale,
                        // pia) show a short blurb + one button; config
                        // providers (wireguard, openvpn) show name + tunnel/
                        // profile fields; netextender shows the full
                        // server/domain/user/password form.
                        Loader {
                            id: addFormLoader
                            visible: shell.vpnAddingProvider !== ""
                            width: parent.width
                            active: visible
                            sourceComponent: {
                                switch (shell.vpnAddingProvider) {
                                case "tailscale":   return tailscaleAddForm;
                                case "pia":         return piaAddForm;
                                case "wireguard":   return wireguardAddForm;
                                case "openvpn":     return openvpnAddForm;
                                case "netextender": return netextenderAddForm;
                                default:            return null;
                                }
                            }
                            onLoaded: addDropdown.currentIndex = -1
                        }
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

    // ---- VPN provider row ----
    // Active provider list entry: icon + name + status, plus connect/
    // disconnect/configure/setup/remove actions. The configure button
    // toggles an inline fields[] editor — one provider at a time via
    // shell.vpnEditing. Each field renders a TextField; Save writes
    // back via VpnService.setFieldValue. nm-kind providers have empty
    // fields[] (NM owns their settings) — Configure is hidden then.
    // Remove asks for confirmation inline (mutex with the editor).
    Component {
        id: vpnRow

        Rectangle {
            id: row
            required property var modelData
            readonly property var p: row.modelData
            readonly property bool expanded: shell.vpnEditing === p.id
            readonly property bool confirming: shell.vpnConfirmRemove === p.id
            // `Array.isArray(p.fields)` is false even when fields is a real
            // array, because QML's property-var marshalling re-wraps JS
            // arrays. Duck-type via .length instead.
            readonly property bool hasFields: p.fields && p.fields.length > 0

            width: parent ? parent.width : 0
            height: (confirming ? confirmRow.implicitHeight :
                     expanded   ? expandedCol.implicitHeight :
                                  compactRow.implicitHeight) + 16
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
                           p && p.connected ? 0.07 : 0.04)
            Behavior on height { NumberAnimation { duration: 100 } }

            // ---- Compact view (default) ----
            Row {
                id: compactRow
                visible: !row.expanded && !row.confirming
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: p.icon
                    color: p.connected ? Theme.accent : Theme.fgDim
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.iconPx + 2
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - vpnActions.implicitWidth - 2 * parent.spacing
                    spacing: 2

                    Text {
                        text: p.name
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: p.statusLabel
                        color: p.connected ? Theme.accent : Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
                Row {
                    id: vpnActions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Button {
                        visible: row.hasFields
                        iconLeading: 0xF0493   // nf-md-cog (gear)
                        variant: Button.Secondary
                        onTriggered: shell.vpnEditing = p.id
                    }
                    Button {
                        visible: p.connected
                        label: I18n.t("network.action.disconnect")
                        variant: Button.Urgent
                        onTriggered: VpnService.disconnect(p.id)
                    }
                    Button {
                        visible: !p.connected
                        label: I18n.t("network.action.connect")
                        variant: Button.Primary
                        onTriggered: VpnService.connect(p.id)
                    }
                    Button {
                        visible: p.canSetup
                        label: I18n.t("network.vpn.setup")
                        variant: Button.Secondary
                        onTriggered: VpnService.setup(p.id)
                    }
                    Button {
                        label: I18n.t("network.vpn.remove_action")
                        variant: Button.Urgent
                        onTriggered: {
                            shell.vpnEditing = "";
                            shell.vpnConfirmRemove = row.p.id;
                        }
                    }
                }
            }

            // ---- Confirm-remove prompt ----
            // Inline replacement of the action row so we don't need a
            // modal scrim. Same pattern the Wi-Fi PSK prompt uses.
            Row {
                id: confirmRow
                visible: row.confirming
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⚠"
                    color: Theme.urgent
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.iconPx + 2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - confirmActions.implicitWidth - 2 * parent.spacing
                    wrapMode: Text.WordWrap
                    text: I18n.t("network.vpn.confirm_remove").replace("{0}", p.name)
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 1
                }
                Row {
                    id: confirmActions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnConfirmRemove = ""
                    }
                    Button {
                        label: I18n.t("network.vpn.remove_action")
                        variant: Button.Urgent
                        onTriggered: {
                            VpnService.removeProvider(row.p.id);
                            shell.vpnConfirmRemove = "";
                        }
                    }
                }
            }

            // ---- Expanded view (fields editor) ----
            Column {
                id: expandedCol
                visible: row.expanded && !row.confirming
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 10
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: p.icon
                        color: p.connected ? Theme.accent : Theme.fgDim
                        font.family: Theme.iconFamily
                        font.pixelSize: Theme.iconPx + 2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: p.name
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        font.bold: true
                    }
                }

                // One row per field. Renders TextField for free-text
                // fields and Dropdown for type:"dropdown" fields. Save
                // writes every dirty field via VpnService.setFieldValue.
                Repeater {
                    id: fieldRepeater
                    model: p.fields
                    delegate: Column {
                        id: fieldCol
                        required property var modelData
                        readonly property var f: fieldCol.modelData
                        readonly property bool isDropdown: f && f.type === "dropdown"
                        readonly property bool isSecret:   f && f.type === "secret"
                        width: expandedCol.width
                        spacing: 4

                        // Secrets start empty in the editor — we never
                        // expose the stored value. Leaving blank on Save
                        // means "keep current".
                        property string editedValue: fieldCol.isSecret ? "" : String(f.value || "")

                        // Populate dropdown options on first render for fields
                        // that declare an optionsCmd. loadFieldOptions is a
                        // no-op when options are already cached.
                        Component.onCompleted: {
                            if (isDropdown) VpnService.loadFieldOptions(row.p.id, f.key);
                        }

                        Text {
                            text: f.label || f.key
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 2
                            font.bold: true
                        }

                        // Free-text fallback (default). Sync editedValue
                        // on every text change — clicking Save doesn't
                        // move focus out of the TextField, so relying on
                        // editingFinished alone misses the latest typed
                        // value. Secrets use echoMode:Password and a
                        // placeholder that hints "leave blank to keep
                        // current" so the user knows the existing
                        // keyring entry isn't being wiped.
                        TextField {
                            visible: !fieldCol.isDropdown
                            width: parent.width
                            text: fieldCol.editedValue
                            echoMode: (fieldCol.isSecret || f.secret === true)
                                         ? TextInput.Password
                                         : TextInput.Normal
                            placeholder: fieldCol.isSecret
                                            ? "•••••• (leave blank to keep current)"
                                            : (f.help || "")
                            onTextChanged: fieldCol.editedValue = text
                            onAccepted: (t) => fieldCol.editedValue = t
                        }

                        // Dropdown for type:"dropdown" fields. Options are
                        // strings; the model rebinds when VpnService loads them.
                        // currentIndex tracks editedValue so a reload doesn't
                        // wipe the selection.
                        Dropdown {
                            id: dd
                            visible: fieldCol.isDropdown
                            width: parent.width
                            model: VpnService.getFieldOptions(row.p.id, f.key)
                            placeholder: f.help || ""
                            // Keep currentIndex in sync with editedValue. We
                            // do this in a binding instead of imperative set
                            // so reloads (options arrive after open) re-find
                            // the selection.
                            currentIndex: {
                                if (!fieldCol.isDropdown) return -1;
                                const opts = VpnService.getFieldOptions(row.p.id, f.key);
                                return opts.indexOf(fieldCol.editedValue);
                            }
                            onSelected: (index, item) => {
                                if (typeof item === "string") fieldCol.editedValue = item;
                            }
                        }

                        Text {
                            visible: !!f.help && !fieldCol.isDropdown
                            text: f.help || ""
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 3
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnEditing = ""
                    }
                    Button {
                        label: I18n.t("network.vpn.save")
                        variant: Button.Primary
                        onTriggered: {
                            // Split dirty fields into:
                            //   - regular fields (server, domain, …) → setFieldValues → jq → JSON
                            //   - secret fields (type:secret, e.g. password) → updateSecret → keyring
                            // Empty secret fields are skipped — leaving
                            // the field blank means "keep the existing
                            // keyring entry".
                            const updates = {};
                            for (let i = 0; i < fieldRepeater.count; i++) {
                                const item = fieldRepeater.itemAt(i);
                                if (!item) continue;
                                if (item.isSecret) {
                                    if (item.editedValue && item.editedValue.length > 0) {
                                        VpnService.updateSecret(row.p.id, item.editedValue);
                                    }
                                    continue;
                                }
                                const before = String(item.f.value || "");
                                if (item.editedValue !== before) {
                                    updates[item.f.key] = item.editedValue;
                                }
                            }
                            if (Object.keys(updates).length > 0) {
                                VpnService.setFieldValues(row.p.id, updates);
                            }
                            shell.vpnEditing = "";
                        }
                    }
                }
            }
        }
    }

    // ---- Provider-specific Add form components ----
    // Each shares the same outer Rectangle chrome (rounded card, fgDim
    // bg) and a header + body + footer Column. The body content differs
    // per provider.

    // Helper: build the standard outer card. Used inline by each form.
    // (Components don't compose well as wrappers in QML, so we just
    // duplicate the chrome; the diff per form is small.)

    Component {
        id: tailscaleAddForm

        Rectangle {
            width: parent ? parent.width : 0
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: I18n.t("network.vpn.add.tailscale.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: I18n.t("network.vpn.add.tailscale.info")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    wrapMode: Text.WordWrap
                }
                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnAddingProvider = ""
                    }
                    Button {
                        label: I18n.t("network.vpn.add.tailscale.signin")
                        variant: Button.Primary
                        onTriggered: {
                            VpnService.addTailscale();
                            shell.vpnAddingProvider = "";
                        }
                    }
                }
            }
        }
    }

    Component {
        id: piaAddForm

        Rectangle {
            width: parent ? parent.width : 0
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Text {
                    text: I18n.t("network.vpn.add.pia.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: I18n.t("network.vpn.add.pia.info")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.pia.user_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: piaUser
                        width: parent.width
                        placeholder: I18n.t("network.vpn.add.pia.user_placeholder")
                    }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.pia.password_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: piaPassword
                        width: parent.width
                        echoMode: TextInput.Password
                        placeholder: "••••••••"
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnAddingProvider = ""
                    }
                    Button {
                        label: I18n.t("network.vpn.add.pia.signin")
                        variant: Button.Primary
                        enabled: piaUser.text.trim().length > 0
                                 && piaPassword.text.length > 0
                        onTriggered: {
                            if (!enabled) return;
                            VpnService.addPia(piaUser.text.trim(), piaPassword.text);
                            shell.vpnAddingProvider = "";
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wireguardAddForm

        Rectangle {
            width: parent ? parent.width : 0
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: I18n.t("network.vpn.add.wireguard.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: I18n.t("network.vpn.add.field.name")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: wgName
                        width: parent.width
                        placeholder: I18n.t("network.vpn.add.wireguard.name_placeholder")
                        onAccepted: (t) => wgAdd.trigger()
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: I18n.t("network.vpn.add.wireguard.tunnel_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: wgTunnel
                        width: parent.width
                        placeholder: "wg0"
                        text: "wg0"
                        onAccepted: (t) => wgAdd.trigger()
                    }
                    Text {
                        width: parent.width
                        text: wgTunnel.text.trim().length > 0
                                ? "/etc/wireguard/" + wgTunnel.text.trim() + ".conf"
                                : ""
                        color: Theme.fgDim
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontPx - 3
                    }
                    Text {
                        width: parent.width
                        text: I18n.t("network.vpn.add.wireguard.tunnel_help")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnAddingProvider = ""
                    }
                    Button {
                        id: wgAdd
                        label: I18n.t("network.vpn.add_create_action")
                        variant: Button.Primary
                        enabled: wgName.text.trim().length > 0 && wgTunnel.text.trim().length > 0
                        function trigger() {
                            if (!enabled) return;
                            VpnService.addWireguard(wgName.text.trim(), wgTunnel.text.trim());
                            shell.vpnAddingProvider = "";
                        }
                        onTriggered: trigger()
                    }
                }
            }
        }
    }

    Component {
        id: openvpnAddForm

        Rectangle {
            width: parent ? parent.width : 0
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: I18n.t("network.vpn.add.openvpn.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: I18n.t("network.vpn.add.field.name")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: ovName
                        width: parent.width
                        placeholder: I18n.t("network.vpn.add.openvpn.name_placeholder")
                        onAccepted: (t) => ovAdd.trigger()
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: I18n.t("network.vpn.add.openvpn.profile_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: ovProfile
                        width: parent.width
                        placeholder: "client"
                        text: "client"
                        onAccepted: (t) => ovAdd.trigger()
                    }
                    Text {
                        width: parent.width
                        text: ovProfile.text.trim().length > 0
                                ? "/etc/openvpn/client/" + ovProfile.text.trim() + ".conf"
                                : ""
                        color: Theme.fgDim
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontPx - 3
                    }
                    Text {
                        width: parent.width
                        text: I18n.t("network.vpn.add.openvpn.profile_help")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnAddingProvider = ""
                    }
                    Button {
                        id: ovAdd
                        label: I18n.t("network.vpn.add_create_action")
                        variant: Button.Primary
                        enabled: ovName.text.trim().length > 0 && ovProfile.text.trim().length > 0
                        function trigger() {
                            if (!enabled) return;
                            VpnService.addOpenvpn(ovName.text.trim(), ovProfile.text.trim());
                            shell.vpnAddingProvider = "";
                        }
                        onTriggered: trigger()
                    }
                }
            }
        }
    }

    Component {
        id: netextenderAddForm

        Rectangle {
            width: parent ? parent.width : 0
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Text {
                    text: I18n.t("network.vpn.add.netextender.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.bold: true
                }

                // Reusable mini field block — Column with label + TextField.
                // Avoid extracting a Component for it; the form's only
                // 5 fields long, inline is clearer.
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.field.name")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField { id: nxName; width: parent.width; placeholder: I18n.t("network.vpn.add.netextender.name_placeholder") }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.netextender.server_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField { id: nxServer; width: parent.width; placeholder: "vpn.example.com" }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.netextender.domain_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField { id: nxDomain; width: parent.width; placeholder: "MYDOMAIN" }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.netextender.user_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField { id: nxUser; width: parent.width; placeholder: "john" }
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: I18n.t("network.vpn.add.netextender.password_label")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        font.bold: true
                    }
                    TextField {
                        id: nxPassword
                        width: parent.width
                        echoMode: TextInput.Password
                        placeholder: I18n.t("network.vpn.add.netextender.password_placeholder")
                    }
                    Text {
                        width: parent.width
                        text: I18n.t("network.vpn.add.netextender.password_help")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    Button {
                        label: I18n.t("network.vpn.cancel")
                        variant: Button.Secondary
                        onTriggered: shell.vpnAddingProvider = ""
                    }
                    Button {
                        id: nxAdd
                        label: I18n.t("network.vpn.add_create_action")
                        variant: Button.Primary
                        enabled: nxName.text.trim().length > 0
                                 && nxServer.text.trim().length > 0
                                 && nxDomain.text.trim().length > 0
                                 && nxUser.text.trim().length > 0
                                 && nxPassword.text.length > 0
                        onTriggered: {
                            if (!enabled) return;
                            VpnService.addNetextender(
                                nxName.text.trim(),
                                nxServer.text.trim(),
                                nxDomain.text.trim(),
                                nxUser.text.trim(),
                                nxPassword.text);
                            shell.vpnAddingProvider = "";
                        }
                    }
                }
            }
        }
    }
}
