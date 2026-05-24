import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Bluetooth status icon. Polls `bluetoothctl show` every 5 s for the
// adapter's power state. Click → launch/focus `bluetui` in a floating
// foot (same convention as btop / wiremix).
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

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.width

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width:  iconText.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color:  hover.containsMouse ? Theme.hot : "transparent"

        Text {
            id: iconText
            anchors.centerIn: parent
            text: root.icon
            color: root.powered ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NiriService.launchTui("bluetui")
        }
    }
}
