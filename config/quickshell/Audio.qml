import QtQuick
import Quickshell.Services.Pipewire

// Default-sink volume + mute indicator.
//   Left click     → toggle mute
//   Right click    → launch/focus `wiremix` (per-app TUI mixer) in a floating kitty
//   Scroll up/down → adjust volume by 5 %
Item {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    implicitHeight: Theme.barHeight
    implicitWidth: pill.implicitWidth

    // Keep the sink node "live" so its audio sub-properties update reactively.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // Wiremix launcher / focuser — delegates to NiriService.launchTui.
    function launchOrFocusWiremix() { NiriService.launchTui("wiremix"); }

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        implicitWidth: row.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color: hover.containsMouse ? Theme.hot : "transparent"

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Material Design Icons via Nerd Font
                //   muted   nf-md-volume_mute    󰝟
                //   high    nf-md-volume_high    󰕾
                //   medium  nf-md-volume_medium  󰖀
                //   low     nf-md-volume_low     󰕿
                text: root.muted
                      ? "󰝟"
                      : (root.volume > 0.66
                         ? "󰕾"
                         : (root.volume > 0.33
                            ? "󰖀"
                            : "󰕿"))
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.muted ? "muted" : Math.round(root.volume * 100) + "%"
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                opacity: 0.85
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    root.launchOrFocusWiremix();
                    return;
                }
                if (root.sink && root.sink.audio)
                    root.sink.audio.muted = !root.sink.audio.muted;
            }
            onWheel: (wheel) => {
                if (!root.sink || !root.sink.audio) return;
                const step = 0.05;
                const delta = wheel.angleDelta.y > 0 ? step : -step;
                root.sink.audio.volume = Math.max(0, Math.min(1,
                    root.sink.audio.volume + delta));
                wheel.accepted = true;
            }
        }
    }
}
