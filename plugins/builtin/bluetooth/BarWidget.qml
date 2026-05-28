import QtQuick
import qs

// Bluetooth bar widget. State comes from BluetoothService — no inline
// bluetoothctl polling here.
//   Left click   → compact popover (power toggle + connected devices + open panel)
//   Right click  → summon the full bluetooth panel
//   The icon mirrors adapter state; the count badge shows connected devices.
Item {
    id: root

    property var barWindow: null

    readonly property bool present:     BluetoothService.present
    readonly property bool enabled:     BluetoothService.enabled
    readonly property bool busy:        BluetoothService.busy
    readonly property bool discovering: BluetoothService.discovering
    readonly property int  connectedCount: BluetoothService.connectedDevices.length

    readonly property string icon:
        !present ? "󰂲"               // nf-md-bluetooth_off
                 : (enabled
                    ? (connectedCount > 0 ? "󰂱"   // nf-md-bluetooth_connect
                                          : "󰂯")  // nf-md-bluetooth (on)
                    : "󰂲")                        // off
    readonly property color iconColor:
        !present ? Theme.fgDim
                 : (enabled ? Theme.fg : Theme.fgDim)

    function openPanel() {
        popover.close();
        Plugins.summon("bluetooth");
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        tooltipText: !root.present
            ? I18n.t("bluetooth.tooltip_none")
            : !root.enabled
                ? I18n.t("bluetooth.tooltip_off")
                : root.connectedCount > 0
                    ? I18n.t("bluetooth.tooltip_connected").replace("{0}", root.connectedCount)
                    : I18n.t("bluetooth.tooltip_on")
        onClicked:      popover.toggle()
        onRightClicked: root.openPanel()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.iconColor
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        // Tiny count badge — only when ≥1 device is connected.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.connectedCount > 0
            text: root.connectedCount
            color: Theme.fg
            font.family: Theme.sansFamily
            font.pixelSize: Theme.barFontPx - 2
            opacity: 0.85
        }
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  280
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:      root.icon
                iconColor: root.iconColor
                title:     I18n.t("bluetooth.title")
                subtitle:  !root.present ? I18n.t("bluetooth.no_adapter")
                         : root.busy     ? I18n.t("bluetooth.busy")
                         : root.enabled  ? (root.connectedCount > 0
                                            ? I18n.t("bluetooth.connected_n")
                                                  .replace("{0}", root.connectedCount)
                                            : I18n.t("bluetooth.on"))
                         : I18n.t("bluetooth.off")
            }

            PopoverDivider {}

            // Brief connected-devices list (max 3) so the popover is a
            // quick at-a-glance status check without opening the panel.
            Column {
                visible: root.enabled && root.connectedCount > 0
                width: parent.width
                spacing: 4

                Repeater {
                    model: BluetoothService.connectedDevices.slice(0, 3)
                    delegate: Row {
                        required property var modelData
                        readonly property var dev: modelData
                        width: parent.width
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BluetoothService.deviceIcon(parent.dev)
                            color: Theme.fg
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.iconPx - 2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28
                            text: BluetoothService.displayName(parent.dev)
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            PopoverDivider { visible: root.enabled && root.connectedCount > 0 }

            PopoverActions {
                visible: root.present

                PopoverButton {
                    label: root.enabled ? I18n.t("bluetooth.turn_off")
                                        : I18n.t("bluetooth.turn_on")
                    variant: root.enabled ? PopoverButton.Secondary : PopoverButton.Primary
                    onTriggered: BluetoothService.togglePower()
                }
                PopoverButton {
                    label: I18n.t("bluetooth.bar.panel")
                    variant: PopoverButton.Primary
                    onTriggered: root.openPanel()
                }
            }
        }
    }
}
