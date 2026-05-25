import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Bluetooth status icon. Polls `bluetoothctl show` every 30 s for the
// adapter's power state.
//   Left click  → popover (power toggle + bluetui link)
//   Right click → launch/focus `bluetui` in a floating foot
// Matches the audio plugin's pattern so the bar behaves uniformly.
Item {
    id: root

    property var barWindow: null

    property bool powered: false
    property bool present: false  // is there any adapter at all?

    readonly property string icon:
        !present ? "󰂲"              // nf-md-bluetooth_off
                : (powered ? "󰂯"   // nf-md-bluetooth
                           : "󰂲")  // nf-md-bluetooth_off

    function refresh() { if (!btProc.running) btProc.running = true }

    Component.onCompleted: refresh()

    Timer {
        // Adapter power state rarely changes; the icon is the only
        // bar-visible signal. 30 s is a fine balance between freshness
        // and not forking bluetoothctl every few seconds.
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: btProc
        // `bluetoothctl show` lists each adapter; we read the first one's
        // Powered line. Exits 0 even with no adapter.
        command: ["bash", "-c",
            "bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }'"]
        stdout: StdioCollector {
            id: btOut
            waitForEnd: true
            onStreamFinished: {
                const t = String(btOut.text || "").trim();
                if (t === "") {
                    root.present = false;
                    root.powered = false;
                } else {
                    root.present = true;
                    root.powered = (t === "yes");
                }
            }
        }
    }

    function togglePower() {
        Quickshell.execDetached(["bash", "-c",
            "bluetoothctl power " + (root.powered ? "off" : "on")]);
        // Optimistic flip; the next poll will reconcile.
        root.powered = !root.powered;
        Qt.callLater(() => root.refresh());
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked:      popover.toggle()
        onRightClicked: NiriService.launchTui("bluetui")

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.powered ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  260
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:      root.icon
                iconColor: root.powered ? Theme.fg : Theme.fgDim
                title:     "Bluetooth"
                subtitle:  !root.present ? "no adapter"
                         : root.powered  ? "on" : "off"
            }

            PopoverDivider {}

            PopoverActions {
                visible: root.present

                PopoverButton {
                    label: root.powered ? "turn off" : "turn on"
                    onTriggered: root.togglePower()
                }
                PopoverButton {
                    label: "bluetui"
                    variant: PopoverButton.Primary
                    onTriggered: {
                        popover.close();
                        NiriService.launchTui("bluetui");
                    }
                }
            }
        }
    }
}
