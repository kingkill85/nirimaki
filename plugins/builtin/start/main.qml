import QtQuick
import qs

// Omarchy-style "start" button — the leftmost item on the bar. Click
// opens the settings menu (Nirimaki's drilldown menu, the analog of
// omarchy-menu). Mirrors Omarchy's custom/omarchy logo module.
Item {
    id: root

    property var barWindow: null

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: Plugins.isSummoned("settings-menu")
        tooltipText: I18n.t("start.tooltip")
        onClicked: Plugins.toggle("settings-menu", "")

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "◉"                       // maki-roll cross-section
            color: Theme.accent
            font.family: Theme.sansFamily
            font.pixelSize: Theme.iconPx
        }
    }
}
