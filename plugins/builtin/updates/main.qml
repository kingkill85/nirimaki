import QtQuick
import Quickshell
import qs

// Pacman + AUR + Nirimaki update-count indicator. Reads from
// UpdatesService (singleton) so we don't fan out simultaneous queries
// on a multi-monitor setup.
//
// Position modelled on Omarchy waybar's `custom/update` (modules-
// center, right of the clock). Icon kept as nf-md-package_up per user
// preference over Omarchy's codicons "package" glyph. Click opens a
// dropdown with the per-source breakdown and a Run-update button —
// same popup shape as the Network / Media / Weather pills so the bar
// looks coherent.
Item {
    id: root

    property var barWindow: null
    property bool popupOpen: false

    readonly property int count: UpdatesService.count
    readonly property bool any: UpdatesService.any

    implicitHeight: Theme.barHeight
    implicitWidth:  any ? pill.width : 0
    visible: any

    function runUpdate() {
        root.popupOpen = false;
        // Same flow as the keybind / Settings → Update entry — TUI in
        // a floating foot via NiriService.
        NiriService.launchTui("nirimaki-update", "bash", "-lc",
            Quickshell.env("HOME") + "/.local/bin/nirimaki-update");
    }

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width:  rowLabel.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color:  (hover.containsMouse || root.popupOpen) ? Theme.hot : "transparent"

        Row {
            id: rowLabel
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
            onClicked: root.popupOpen = !root.popupOpen
        }
    }

    // ---------------- Popup ----------------
    PopupWindow {
        id: popup
        visible: root.popupOpen
        color: "transparent"

        property real popupX: 0
        anchor.window: root.barWindow
        anchor.rect.x: popupX
        anchor.rect.y: root.barWindow ? root.barWindow.height : 0

        onVisibleChanged: {
            if (visible) {
                popupX = pill.mapToItem(root.barWindow.contentItem, 0, 0).x
                       + (pill.width - implicitWidth) / 2;
                PopupBus.show(root);
                Qt.callLater(() => keyCatcher.forceActiveFocus());
            } else {
                PopupBus.hide(root);
                if (root.popupOpen) root.popupOpen = false;
            }
        }

        implicitWidth:  280
        implicitHeight: card.implicitHeight + 24

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.popupOpen = false
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: Theme.cardBorderWidth
        }

        Column {
            id: card
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Header row: icon + total count.
            Row {
                spacing: 10
                width: parent.width

                Text {
                    text: "󰚰"
                    color: Theme.fg
                    font.family: Theme.iconFamily
                    font.pixelSize: 22
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: I18n.t("updates.title")
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        font.bold: true
                    }
                    Text {
                        text: root.count + " " + (root.count === 1
                                                  ? I18n.t("updates.one")
                                                  : I18n.t("updates.many"))
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.fgDim
                opacity: 0.25
            }

            // Per-source breakdown — only rows with a non-zero count.
            Grid {
                columns: 2
                columnSpacing: 14
                rowSpacing: 4
                width: parent.width

                Text {
                    visible: UpdatesService.pacmanCount > 0
                    text: "pacman"; color: Theme.fgDim
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }
                Text {
                    visible: UpdatesService.pacmanCount > 0
                    text: UpdatesService.pacmanCount; color: Theme.fg
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }

                Text {
                    visible: UpdatesService.aurCount > 0
                    text: "AUR"; color: Theme.fgDim
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }
                Text {
                    visible: UpdatesService.aurCount > 0
                    text: UpdatesService.aurCount; color: Theme.fg
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }

                Text {
                    visible: UpdatesService.nirimakiCount > 0
                    text: "Nirimaki"; color: Theme.fgDim
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }
                Text {
                    visible: UpdatesService.nirimakiCount > 0
                    text: UpdatesService.nirimakiCount; color: Theme.fg
                    font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2
                }
            }

            // Run-update button.
            Rectangle {
                width: parent.width
                height: 30
                radius: Theme.radius
                color: runHover.containsMouse
                       ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                       : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: I18n.t("updates.run")
                    color: Theme.accent
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 1
                    font.bold: true
                }

                MouseArea {
                    id: runHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runUpdate()
                }
            }
        }
    }
}
