import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Recording-active indicator. Polls `pgrep -x wf-recorder` every 2 s and
// only renders when a recording is in progress. Click → run
// nirimaki-screenrecord which sees the running process and toggles it off.
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
    implicitWidth:  recording ? pill.implicitWidth : 0
    visible: recording

    BarPill {
        id: pill
        onClicked: {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/nirimaki-screenrecord"]);
            Qt.callLater(() => root.refresh());
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // nf-md-record_rec — solid filled record dot.
            text: "󰻂"
            color: Theme.urgent      // red, matches Omarchy's `.active` class
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    // Subtle pulse so the dot reads as "live" rather than static.
    SequentialAnimation {
        running: root.recording
        loops:   Animation.Infinite
        NumberAnimation { target: pill; property: "opacity"; from: 1.0; to: 0.55; duration: 700 }
        NumberAnimation { target: pill; property: "opacity"; from: 0.55; to: 1.0; duration: 700 }
    }
}
