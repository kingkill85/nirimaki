import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs

// Floating toast stack — one instance per screen via internal Variants.
// (Was wrapped by Variants in shell.qml before plugin migration; now
// self-contained so it can drop in as a `mount: "toast"` plugin without
// the host needing to know about per-screen multiplexing.)
// Layer=Overlay, no keyboard focus, no exclusion — passive surface.
Item {
    id: hostRoot

    Variants {
        model: Quickshell.screens

    delegate: PanelWindow {
        id: root
        required property ShellScreen modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "nirimaki-notification-toast"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; right: true }
        margins.top:   Theme.barHeight + 12
        margins.right: Theme.padX

        visible: NotificationService.popups.length > 0
        implicitWidth:  column.implicitWidth
        implicitHeight: column.implicitHeight

        ColumnLayout {
            id: column
            anchors.top: parent.top
            anchors.right: parent.right
            spacing: 8

            Repeater {
                model: NotificationService.popups

                delegate: Rectangle {
                    id: toastCard
                    required property var modelData
                    required property int index

                    Layout.preferredWidth: 380
                    Layout.alignment: Qt.AlignRight

                    implicitHeight: contentCol.implicitHeight + 24
                    radius: Theme.radius
                    color: Theme.cardBg
                    border.color: Theme.cardBorderColor
                    border.width: Theme.cardBorderWidth

                    readonly property real lifetime:
                        NotificationService.durationFor(modelData.urgency, modelData.expireTimeout)
                    property real progress: 1.0
                    readonly property bool ticking:
                        lifetime > 0 && !mouse.containsMouse

                    Timer {
                        interval: 50
                        repeat: true
                        running: ticking
                        onTriggered: {
                            if (lifetime <= 0) return;
                            progress -= 50.0 / lifetime;
                            if (progress <= 0) {
                                progress = 0;
                                NotificationService.dismiss(index);
                            }
                        }
                    }

                    Column {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 12
                        anchors.bottomMargin: lifetime > 0 ? 14 : 12   // room for bar
                        spacing: 4

                        Text {
                            text: modelData.summary || ""
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx + 1
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.body || ""
                            visible: text !== ""
                            color: Theme.fg
                            opacity: 0.85
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 1
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 3
                            width: parent.width
                        }
                        Text {
                            text: modelData.app || ""
                            visible: text !== ""
                            color: Theme.fgDim
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 3
                        }

                        // Action buttons (Reply / Mark as read / …). z:1 so
                        // each button's MouseArea wins over the card-wide
                        // dismiss handler below.
                        Row {
                            id: actionRow
                            visible: (modelData.actions || []).length > 0
                            anchors.right: parent.right
                            spacing: 6
                            topPadding: 4
                            z: 1

                            Repeater {
                                model: toastCard.modelData.actions || []
                                delegate: Rectangle {
                                    id: actionBtn
                                    required property var modelData
                                    radius: Theme.radius * 0.6
                                    implicitWidth: actionLabel.implicitWidth + 18
                                    implicitHeight: actionLabel.implicitHeight + 10
                                    color: actionMouse.containsMouse
                                        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
                                        : "transparent"
                                    border.color: Theme.cardBorderColor
                                    border.width: Theme.cardBorderWidth

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: actionBtn.modelData.text
                                        color: Theme.fg
                                        font.family: Theme.sansFamily
                                        font.pixelSize: Theme.fontPx - 2
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: NotificationService.invokeAction(
                                            toastCard.index, actionBtn.modelData.identifier)
                                    }
                                }
                            }
                        }
                    }

                    // Lifetime progress bar at the bottom.
                    Rectangle {
                        visible: lifetime > 0
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: 1
                        anchors.bottomMargin: 1
                        height: 2
                        width: (parent.width - 2) * progress
                        color: Theme.fg
                        opacity: 0.6
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        // Left-click activates the default action (e.g. opens
                        // the chat conversation) then clears; middle-click just
                        // clears.
                        onClicked: (e) => e.button === Qt.MiddleButton
                            ? NotificationService.dismiss(index)
                            : NotificationService.activate(index)
                    }
                }
            }
        }
    }
    }
}
