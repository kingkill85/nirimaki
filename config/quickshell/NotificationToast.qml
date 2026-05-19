import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Floating toast stack per screen. One instance per output via Variants.
// Layer=Overlay, no keyboard focus, no exclusion — passive surface.
PanelWindow {
    id: root
    required property ShellScreen modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-notification-toast"
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
                    NotificationService.durationFor(modelData.urgency)
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
                    onClicked: NotificationService.dismiss(index)
                }
            }
        }
    }
}
