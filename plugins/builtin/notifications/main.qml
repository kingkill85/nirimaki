import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs

// Bar widget — notification bell + center.
//   Left click  → open the notification center (popover with history)
//   Right click → clear everything (live toasts + history)
//
// Toasts auto-expire from the on-screen stack into NotificationService's
// `history` list (see NotificationService._archive); this widget is the
// place they go to be reviewed and cleared later, so chat-webapp toasts
// no longer have to be hand-dismissed one by one.
Item {
    id: root

    property var barWindow: null

    readonly property int  activeCount: NotificationService.count
    readonly property int  histCount:   NotificationService.historyCount
    readonly property bool anyActive:    activeCount > 0
    // Number on the pill: pending toasts while any are live, otherwise the
    // backlog waiting in the center.
    readonly property int  badge:        anyActive ? activeCount : histCount
    readonly property bool shown:        anyActive || histCount > 0

    // Bell stays out of the bar entirely when there's nothing live and
    // nothing archived.
    implicitHeight: Theme.barHeight
    implicitWidth:  shown ? pill.implicitWidth : 0
    visible: shown

    function clearAll() {
        NotificationService.dismissAll();   // archives, then…
        NotificationService.clearHistory(); // …wipe the backlog
        popover.close();
    }

    BarPill {
        id: pill
        active: popover.popupOpen
        tooltipText: I18n.t("notifications.tooltip")
        onClicked: popover.toggle()
        onRightClicked: root.clearAll()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.anyActive ? "󰂜" : "󰂚"   // bell-alert : bell
            color: root.anyActive ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
        Text {
            visible: root.badge > 0
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.badge)
            color: root.anyActive ? Theme.fg : Theme.fgDim
            font.family: Theme.sansFamily
            font.pixelSize: Theme.barFontPx - 2
        }
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  360
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:     "󰂚"
                title:    I18n.t("notifications.title")
                subtitle: root.histCount + " " + (root.histCount === 1
                              ? I18n.t("notifications.one")
                              : I18n.t("notifications.many"))
            }

            PopoverDivider {}

            Text {
                visible: root.histCount === 0
                width: parent.width
                text: I18n.t("notifications.empty")
                color: Theme.fgDim
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 1
                topPadding: 8
                bottomPadding: 8
            }

            ListView {
                id: list
                visible: root.histCount > 0
                width: parent.width
                height: Math.min(contentHeight, 360)
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: NotificationService.history

                delegate: Rectangle {
                    id: histCard
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    implicitHeight: histCol.implicitHeight + 12
                    radius: Theme.radius
                    color: rowHover.containsMouse ? Theme.hot : "transparent"

                    readonly property bool critical:
                        modelData.urgency === NotificationUrgency.Critical

                    // Click an actionable entry to fire its default action —
                    // jumps the webapp (e.g. Teams) to the originating
                    // conversation, the same handler the toast click uses.
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: histCard.modelData.actionable
                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (histCard.modelData.actionable) {
                                NotificationService.activateHistory(histCard.index);
                                popover.close();
                            }
                        }
                    }

                    // Remove-this-one affordance, top-right. Fades in on hover.
                    Text {
                        id: rm
                        anchors { top: parent.top; right: parent.right
                                  topMargin: 6; rightMargin: 8 }
                        text: "✕"
                        color: rmHover.containsMouse ? Theme.urgent : Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        opacity: (rowHover.containsMouse || rmHover.containsMouse) ? 1.0 : 0.0

                        MouseArea {
                            id: rmHover
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.removeFromHistory(histCard.index)
                        }
                    }

                    Column {
                        id: histCol
                        anchors {
                            left: parent.left;   leftMargin: 10
                            right: parent.right;  rightMargin: rm.width + 16
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 2

                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                id: appText
                                width: parent.width - timeText.implicitWidth - parent.spacing
                                text: histCard.modelData.app || ""
                                color: histCard.critical ? Theme.urgent : Theme.fgDim
                                elide: Text.ElideRight
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 3
                                font.bold: true
                            }
                            Text {
                                id: timeText
                                anchors.baseline: appText.baseline
                                text: Qt.formatDateTime(
                                          new Date(histCard.modelData.timestamp), "HH:mm")
                                color: Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 3
                            }
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: histCard.modelData.summary || ""
                            color: Theme.fg
                            elide: Text.ElideRight
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            font.bold: true
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: histCard.modelData.body || ""
                            color: Theme.fg
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 2
                        }
                    }
                }
            }

            PopoverDivider { visible: root.histCount > 0 }

            PopoverActions {
                visible: root.histCount > 0
                PopoverButton {
                    label: I18n.t("notifications.clear")
                    variant: PopoverButton.Secondary
                    onTriggered: root.clearAll()
                }
            }
        }
    }
}
