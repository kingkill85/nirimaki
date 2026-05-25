import QtQuick
import qs

// Full bluetooth device manager — lazy-summoned overlay.
//
//   quickshell ipc call shell summon bluetooth
//
// Two tabs:
//   1. DEVICES   connected / paired / available, each device a row
//                with connect/disconnect/pair/forget actions
//   2. ADAPTER   power + discoverable + pairable toggles, adapter info
//
// Reads/writes state via BluetoothService, which wraps
// Quickshell.Bluetooth (BlueZ via DBus). The two tabs mirror the audio
// panel's pattern so behaviour is uniform across service panels.
DialogShell {
    id: shell
    open: true
    cardWidth: 540
    cardHeight: 560
    dialogNamespace: "nirimaki-bluetooth-panel"

    onCloseRequested: Plugins.hide("bluetooth")

    property int currentTab: 0   // 0 = devices, 1 = adapter

    // Localised state labels for the BluetoothService subtitle helper.
    // The service has no I18n dependency by design (it must stay a pure
    // wrapper around the QML module), so we feed it the strings here.
    Connections {
        target: I18n
        function onLocaleChanged() { shell._refreshLabels(); }
    }
    Component.onCompleted: shell._refreshLabels()
    function _refreshLabels() {
        BluetoothService._connectedLabel = I18n.t("bluetooth.state.connected");
        BluetoothService._pairedLabel    = I18n.t("bluetooth.state.paired");
        BluetoothService._pairingLabel   = I18n.t("bluetooth.state.pairing");
    }

    Item {
        width: 0; height: 0
        focus: true
        Keys.onEscapePressed: Plugins.hide("bluetooth")
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
                text: BluetoothService.present && BluetoothService.enabled ? "󰂯" : "󰂲"
                color: BluetoothService.enabled ? Theme.fg : Theme.fgDim
                font.family: Theme.iconFamily
                font.pixelSize: Theme.fontPxLarge + 4
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: parent.width - 80 - parent.spacing * 2 - 28

                Text {
                    text: I18n.t("bluetooth.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                }
                Text {
                    text: I18n.t("bluetooth.summary")
                          .replace("{0}", BluetoothService.connectedDevices.length)
                          .replace("{1}", BluetoothService.pairedDevices.length)
                          .replace("{2}", BluetoothService.availableDevices.length)
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                }
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.t("bluetooth.close")
                onTriggered: Plugins.hide("bluetooth")
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
                I18n.t("bluetooth.tab.devices"),
                I18n.t("bluetooth.tab.adapter")
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

            // ---------------- DEVICES tab ----------------
            // Pure ScrollView won't size its column to its width
            // (see session-handoff gotcha 5) — use a Flickable with
            // explicit contentWidth + width-bound column.
            Item {
                visible: shell.currentTab === 0
                anchors.fill: parent

                // Empty state: no adapter at all.
                Text {
                    anchors.centerIn: parent
                    visible: !BluetoothService.present
                    text: I18n.t("bluetooth.no_adapter_full")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    font.italic: true
                }

                // Empty state: adapter exists but powered off.
                Column {
                    anchors.centerIn: parent
                    visible: BluetoothService.present && !BluetoothService.enabled
                    spacing: 12
                    width: 320

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰂲"
                        color: Theme.fgDim
                        font.family: Theme.iconFamily
                        font.pixelSize: Theme.fontPxLarge + 12
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("bluetooth.empty_off")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        label: I18n.t("bluetooth.turn_on")
                        variant: Button.Primary
                        onTriggered: BluetoothService.setEnabled(true)
                    }
                }

                Flickable {
                    id: devicesFlick
                    visible: BluetoothService.present && BluetoothService.enabled
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: devicesCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: devicesCol
                        width: devicesFlick.width
                        spacing: 14

                        // ----- CONNECTED -----
                        Text {
                            visible: BluetoothService.connectedDevices.length > 0
                            text: I18n.t("bluetooth.section.connected")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 2
                            font.bold: true
                            font.letterSpacing: 2
                        }
                        Repeater {
                            model: BluetoothService.connectedDevices
                            delegate: deviceRow
                        }

                        // ----- PAIRED (known but not connected) -----
                        Text {
                            visible: BluetoothService.pairedDevices.length > 0
                            text: I18n.t("bluetooth.section.paired")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 2
                            font.bold: true
                            font.letterSpacing: 2
                        }
                        Repeater {
                            model: BluetoothService.pairedDevices
                            delegate: deviceRow
                        }

                        // ----- AVAILABLE (unpaired, populated by scan) -----
                        // Header is two anchored siblings inside an Item — a
                        // Row with a fixed-px spacer overflows when the localised
                        // button label is wider than guessed (e.g. "Suche stoppen"
                        // in German).
                        Item {
                            width: parent.width
                            // Button has fixed `height: Theme.controlHeight` and no
                            // implicitHeight, so we anchor to the theme constant
                            // directly to give this header row a real height.
                            height: Theme.controlHeight

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t("bluetooth.section.available")
                                color: Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 2
                                font.bold: true
                                font.letterSpacing: 2
                            }
                            Button {
                                id: scanBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: BluetoothService.discovering
                                       ? I18n.t("bluetooth.scan_stop")
                                       : I18n.t("bluetooth.scan_start")
                                variant: BluetoothService.discovering
                                         ? Button.Urgent : Button.Secondary
                                onTriggered: BluetoothService.toggleScan()
                            }
                        }
                        Repeater {
                            model: BluetoothService.availableDevices
                            delegate: deviceRow
                        }
                        Text {
                            visible: BluetoothService.availableDevices.length === 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: BluetoothService.discovering
                                  ? I18n.t("bluetooth.scanning")
                                  : I18n.t("bluetooth.empty_available")
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            font.italic: true
                        }
                    }
                }
            }

            // ---------------- ADAPTER tab ----------------
            Column {
                visible: shell.currentTab === 1
                width: parent.width
                spacing: 12

                Text {
                    text: I18n.t("bluetooth.section.adapter")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                // Adapter name + address — read-only label.
                Rectangle {
                    visible: BluetoothService.present
                    width: parent.width
                    height: adapterInfo.implicitHeight + 16
                    radius: Theme.radius
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

                    Column {
                        id: adapterInfo
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        spacing: 2

                        Text {
                            text: BluetoothService.adapterName || "—"
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            font.bold: true
                        }
                        Text {
                            visible: BluetoothService.adapter
                                     && BluetoothService.adapter.adapterId
                            text: I18n.t("bluetooth.adapter_id")
                                  .replace("{0}", BluetoothService.adapter
                                                  ? BluetoothService.adapter.adapterId : "")
                            color: Theme.fgDim
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontPx - 2
                        }
                    }
                }

                Item { width: parent.width; height: 4 }

                Text {
                    text: I18n.t("bluetooth.section.controls")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                Toggle {
                    width: parent.width
                    label:       I18n.t("bluetooth.toggle.power")
                    description: I18n.t("bluetooth.toggle.power_desc")
                    checked:     BluetoothService.enabled
                    onToggled:   (v) => BluetoothService.setEnabled(v)
                }
                Toggle {
                    width: parent.width
                    enabled: BluetoothService.enabled
                    opacity: enabled ? 1.0 : 0.5
                    label:       I18n.t("bluetooth.toggle.discoverable")
                    description: I18n.t("bluetooth.toggle.discoverable_desc")
                    checked:     BluetoothService.discoverable
                    onToggled:   (v) => BluetoothService.setDiscoverable(v)
                }
                Toggle {
                    width: parent.width
                    enabled: BluetoothService.enabled
                    opacity: enabled ? 1.0 : 0.5
                    label:       I18n.t("bluetooth.toggle.discovering")
                    description: I18n.t("bluetooth.toggle.discovering_desc")
                    checked:     BluetoothService.discovering
                    onToggled:   (v) => BluetoothService.setDiscovering(v)
                }
            }
        }
    }

    // ---- Device-row component ----
    // Re-used by all three sections; the only behaviour difference is
    // which action buttons are visible based on the device's state.
    Component {
        id: deviceRow

        Rectangle {
            id: row
            required property var modelData
            readonly property var dev: row.modelData

            width: parent ? parent.width : 0
            height: rowBody.implicitHeight + 16
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

            Row {
                id: rowBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: BluetoothService.deviceIcon(row.dev)
                    color: row.dev && row.dev.connected ? Theme.accent : Theme.fg
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.iconPx + 2
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - actions.implicitWidth - 2 * parent.spacing
                    spacing: 2

                    Text {
                        text: BluetoothService.displayName(row.dev) || "—"
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: BluetoothService.deviceSubtitle(row.dev)
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

                    // Connected → "Disconnect"
                    Button {
                        visible: row.dev && row.dev.connected
                        label: I18n.t("bluetooth.action.disconnect")
                        variant: Button.Urgent
                        onTriggered: BluetoothService.disconnectDevice(row.dev)
                    }
                    // Paired (but not connected) → "Connect" + "Forget"
                    Button {
                        visible: row.dev && row.dev.paired && !row.dev.connected
                        label: I18n.t("bluetooth.action.connect")
                        variant: Button.Primary
                        onTriggered: BluetoothService.connectDevice(row.dev)
                    }
                    Button {
                        visible: row.dev && row.dev.paired && !row.dev.connected
                        label: I18n.t("bluetooth.action.forget")
                        variant: Button.Secondary
                        onTriggered: BluetoothService.forgetDevice(row.dev)
                    }
                    // Unpaired → "Pair"  (or "Cancel" while pairing is in flight)
                    Button {
                        visible: row.dev && !row.dev.paired && !row.dev.pairing
                        label: I18n.t("bluetooth.action.pair")
                        variant: Button.Primary
                        onTriggered: BluetoothService.pairDevice(row.dev)
                    }
                    Button {
                        visible: row.dev && row.dev.pairing
                        label: I18n.t("bluetooth.action.cancel")
                        variant: Button.Urgent
                        onTriggered: BluetoothService.cancelPair(row.dev)
                    }
                }
            }
        }
    }
}
