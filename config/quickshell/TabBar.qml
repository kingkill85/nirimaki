import QtQuick

// Tab bar row. Lays out a series of labels horizontally; one is
// highlighted as the current tab. Stateless: emits `tabClicked(index)`,
// caller flips `currentIndex` in response.
//
//   TabBar {
//       width: parent.width
//       tabs: ["Output", "Input", "Apps"]
//       currentIndex: panelTab
//       onTabClicked: (i) => panelTab = i
//   }
//
// Visual: each tab is a small pill-like Rectangle. The active tab gets
// an accent underline + accent text; inactive tabs are fgDim text on
// transparent background, lighting up on hover.
Item {
    id: root

    property var    tabs: []        // [string]
    property int    currentIndex: 0

    signal tabClicked(int index)

    implicitHeight: Theme.controlHeight
    implicitWidth:  rowItem.implicitWidth

    Row {
        id: rowItem
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.tabs

            delegate: Rectangle {
                id: tab
                required property string modelData
                required property int index
                readonly property bool active: index === root.currentIndex

                width:  tabLabel.implicitWidth + 2 * Theme.controlPadX
                height: Theme.controlHeight
                radius: Theme.radius
                color: hover.containsMouse && !active
                       ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)
                       : "transparent"

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: tab.modelData.toUpperCase()
                    color: tab.active ? Theme.accent : Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 1
                    font.bold: true
                    font.letterSpacing: 2
                }

                // Underline for the active tab.
                Rectangle {
                    visible: tab.active
                    width: parent.width - 2 * Theme.controlPadX
                    height: 2
                    radius: 1
                    color: Theme.accent
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tabClicked(tab.index)
                }
            }
        }
    }

    // Thin baseline below the whole tab bar (separates from content).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.fgDim
        opacity: 0.18
    }
}
