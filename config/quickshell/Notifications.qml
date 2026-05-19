import QtQuick
import Quickshell

// Bar widget — bell icon + active count.
//   Left click  → dismiss the topmost popup
//   Right click → dismiss all
Item {
    id: root

    readonly property int count: NotificationService.count
    readonly property bool active: count > 0

    // Bar widget hidden when there's nothing pending — bell stays out of
    // the way until something actually fires.
    implicitHeight: Theme.barHeight
    implicitWidth:  active ? pill.width : 0
    visible: active

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
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.active
                      ? "󰂜"   // nf-md-bell-alert
                      : "󰂚"   // nf-md-bell
                color: root.active ? Theme.fg : Theme.fgDim
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx
            }
            Text {
                visible: root.active
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.count)
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    NotificationService.dismissAll();
                } else if (root.count > 0) {
                    NotificationService.dismiss(0);
                }
            }
        }
    }
}
