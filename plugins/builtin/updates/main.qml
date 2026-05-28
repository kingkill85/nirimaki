import QtQuick
import Quickshell
import qs

// Pacman + AUR + Nirimaki update-count indicator. Reads from
// UpdatesService (singleton) so we don't fan out simultaneous queries
// on a multi-monitor setup.
//
// Position modelled on Omarchy waybar's `custom/update` (modules-
// center, right of the clock). Icon kept as nf-md-package_up per user
// preference over Omarchy's codicons "package" glyph.
Item {
    id: root

    property var barWindow: null

    readonly property int count: UpdatesService.count
    readonly property bool any: UpdatesService.any

    implicitHeight: Theme.barHeight
    implicitWidth:  any ? pill.implicitWidth : 0
    visible: any

    function runUpdate() {
        popover.close();
        NiriService.launchTui("nirimaki-update", "bash", "-lc",
            Quickshell.env("HOME") + "/.local/bin/nirimaki-update");
    }

    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked: popover.toggle()

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
            font.pixelSize: Theme.barFontPx
            opacity: 0.85
        }
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  280
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:     "󰚰"
                title:    I18n.t("updates.title")
                subtitle: root.count + " " + (root.count === 1
                              ? I18n.t("updates.one")
                              : I18n.t("updates.many"))
            }

            PopoverDivider {}

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

            PopoverDivider {}

            PopoverActions {
                PopoverButton {
                    label: I18n.t("updates.run")
                    variant: PopoverButton.Primary
                    onTriggered: root.runUpdate()
                }
            }
        }
    }
}
