import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Pacman + AUR + Nirimaki update-count indicator. Reads from
// UpdatesService (singleton) so we don't fan out simultaneous queries
// on a multi-monitor setup.
//
// Position modelled on Omarchy waybar's `custom/update` (modules-
// center, right of the clock). Icon kept as nf-md-package_up per user
// preference over Omarchy's codicons "package" glyph. Hover shows a
// per-source breakdown — clicking still runs `nirimaki-update`, which
// handles all three sources in one pipeline.
Item {
    id: root

    readonly property int count: UpdatesService.count
    readonly property bool any: UpdatesService.any

    implicitHeight: Theme.barHeight
    implicitWidth:  any ? pill.width : 0
    visible: any

    // Build a tooltip string of the form "3 pacman · 1 AUR · 2 Nirimaki"
    // — only sources with a non-zero count appear, so a single-source
    // tooltip stays short.
    function tooltipText() {
        const parts = [];
        if (UpdatesService.pacmanCount > 0)
            parts.push(UpdatesService.pacmanCount + " pacman");
        if (UpdatesService.aurCount > 0)
            parts.push(UpdatesService.aurCount + " AUR");
        if (UpdatesService.nirimakiCount > 0)
            parts.push(UpdatesService.nirimakiCount + " Nirimaki");
        return parts.join("  ·  ");
    }

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

            // Hover-tooltip with the per-source breakdown. Uses the
            // attached ToolTip from QtQuick.Controls so we don't have
            // to manage a custom popup; the bar's PanelWindow hosts
            // it cleanly because tooltips render in a separate Qt
            // popup-window above the layer-shell surface.
            ToolTip.delay: 400
            ToolTip.timeout: -1
            ToolTip.visible: containsMouse && root.any
            ToolTip.text: root.tooltipText()

            // Same wrapped flow as Settings → Update → Nirimaki: banner +
            // sudo-prime + git pull + paru -Syu + post-update hooks +
            // reboot prompt + pause. UpdatesService's pacman.log
            // FileView refreshes the local counts when paru finishes;
            // the remote count refreshes on the next remote-timer tick.
            onClicked: NiriService.launchTui("nirimaki-update", "bash", "-lc",
                Quickshell.env("HOME") + "/.local/bin/nirimaki-update")
        }
    }
}
