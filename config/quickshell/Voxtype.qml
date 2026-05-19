import QtQuick
import Quickshell
import Quickshell.Io

// Voxtype (push-to-talk dictation) status indicator. Mirrors Omarchy
// waybar's `custom/voxtype` module: idle / recording / transcribing
// states, MDI microphone glyph.
//
// State is read from voxtype's state file at $XDG_RUNTIME_DIR/voxtype/state.
// FileView { watchChanges: true } gives inotify-driven updates so the bar
// flips instantly when F9 is pressed/released or `voxtype record toggle`
// fires from the Mod+Ctrl+X bind.
//
// Hidden entirely when voxtype isn't running (state file absent / empty).
Item {
    id: root

    property string state: ""   // "idle" | "recording" | "transcribing" | ""

    readonly property bool recording:     state === "recording"
    readonly property bool transcribing:  state === "transcribing"
    readonly property bool idle:          state === "idle"
    // Only visible while actively recording or transcribing — idle stays
    // invisible to keep the bar clean.
    readonly property bool any:           recording || transcribing

    function parseState(raw) {
        const s = String(raw || "").trim().toLowerCase();
        root.state = (s === "recording" || s === "transcribing" || s === "idle") ? s : "";
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/voxtype/state"
        watchChanges: true
        printErrors: false
        onLoaded:      root.parseState(text())
        onFileChanged: reload()
        onLoadFailed:  root.parseState("")
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  any ? pill.width : 0
    visible: any

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
            // nf-md-microphone (idle/recording) and nf-md-timer_sand
            // (transcribing). Same glyphs Omarchy waybar maps in its
            // `custom/voxtype.format-icons` block.
            text: root.transcribing ? "󰔟"
                : root.recording    ? "󰍬"
                : "󰍮"   // nf-md-microphone_off — idle
            color: root.recording    ? Theme.urgent
                 : root.transcribing ? Theme.accent
                 : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        // Pulse the icon while actively recording — matches the
        // ScreenRecord indicator's affordance.
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
            // Left-click toggles dictation (same as the Mod+Ctrl+X bind).
            onClicked: Quickshell.execDetached(["voxtype", "record", "toggle"])
        }
    }
}
