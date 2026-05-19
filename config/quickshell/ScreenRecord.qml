import QtQuick
import Quickshell
import Quickshell.Io

// Recording-active indicator. Polls `pgrep -x wf-recorder` every 2 s and
// only renders when a recording is in progress. Click → run
// qs-screenrecord which sees the running process and toggles it off.
//
// Modelled on Omarchy waybar's `custom/screenrecording-indicator`
// (default/waybar/indicators/screen-recording.sh) — same `pgrep`-driven
// visibility, same `class: "active"` styling, mapped to nf-md-record_rec.
Item {
    id: root

    property bool recording: false

    function refresh() { if (!proc.running) proc.running = true; }

    Component.onCompleted: refresh()

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        // `pgrep -x` exits 0 when at least one match, 1 otherwise.
        // Wrap so the script always exits 0 and stdout carries the flag.
        command: ["bash", "-c", "pgrep -x wf-recorder >/dev/null && echo y || echo n"]
        stdout: StdioCollector {
            id: out
            waitForEnd: true
            onStreamFinished: root.recording = String(out.text || "").trim() === "y"
        }
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  recording ? pill.width : 0
    visible: recording

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
            // nf-md-record_rec — solid filled record dot.
            text: "󰻂"
            color: Theme.urgent      // red, matches Omarchy's `.active` class
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        // Subtle pulse so the dot reads as "live" rather than static.
        SequentialAnimation on opacity {
            running: root.recording
            loops:   Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.55; duration: 700 }
            NumberAnimation { from: 0.55; to: 1.0; duration: 700 }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Quickshell.execDetached(["/home/michael/.local/bin/qs-screenrecord"]);
                Qt.callLater(() => root.refresh());
            }
        }
    }
}
