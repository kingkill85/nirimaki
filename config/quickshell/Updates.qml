import QtQuick
import Quickshell
import Quickshell.Io

// Pacman update-count indicator. Reads from UpdatesService (singleton)
// so we don't fan out 3 simultaneous `checkupdates` invocations on a
// multi-monitor setup (the shared pacman-contrib lock makes all but one
// fail).
//
// Position modelled on Omarchy waybar's `custom/update` (modules-center,
// right of the clock). Icon kept as nf-md-package_up per user preference
// over Omarchy's codicons "package" glyph.
Item {
    id: root

    readonly property int count: UpdatesService.count
    readonly property bool any: UpdatesService.any

    implicitHeight: Theme.barHeight
    implicitWidth:  any ? pill.width : 0
    visible: any

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width:  row.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color:  hover.containsMouse ? Theme.hot : "transparent"

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰚰"
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.count
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
            cursorShape: Qt.PointingHandCursor
            // Runs the same wrapped flow as Settings → Update → Nirimaki:
            // banner + sudo-prime + git pull + paru -Syu + feature-state
            // refresh + niri reload + pause. UpdatesService's pacman.log
            // FileView refreshes the count automatically when paru
            // finishes, so no manual refresh here.
            onClicked: NiriService.launchTui("nirimaki-update", "bash", "-lc",
                Quickshell.env("HOME") + "/.local/bin/nirimaki-update")
        }
    }
}
