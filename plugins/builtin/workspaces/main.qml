import QtQuick
import QtQuick.Layouts
import qs

// Workspaces pills for a given niri output.
// Reads from the shared NiriService singleton — no Process of its own.
Item {
    id: root
    // Set by Bar.qml's pluginLoader via `onLoaded` after instantiation.
    // Default "" so the QML engine doesn't warn during the initial frame
    // before onLoaded fires — the workspaces filter just matches nothing
    // for one tick, then populates.
    property string outputName: ""

    implicitHeight: Theme.barHeight
    implicitWidth: row.implicitWidth + 2 * Theme.padX

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Theme.padX
        spacing: Theme.gap

        Repeater {
            model: NiriService.workspaces
                       .filter(w => w.output === root.outputName)
                       .sort((a, b) => a.idx - b.idx)

            delegate: Rectangle {
                required property var modelData
                implicitWidth: Math.max(label.implicitWidth + 2 * Theme.padX,
                                        Theme.barHeight - 2 * Theme.padY)
                implicitHeight: Theme.barHeight - 2 * Theme.padY
                radius: Theme.radius
                color: modelData.is_focused ? Theme.accent
                                            : (modelData.is_active ? Theme.bgAlt : "transparent")
                border.width: modelData.is_active && !modelData.is_focused ? 1 : 0
                border.color: Theme.fgDim

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.name && modelData.name.length
                          ? modelData.name
                          : String(modelData.idx)
                    color: modelData.is_focused ? Theme.bg : Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NiriService.focusWorkspace(modelData.idx)
                }
            }
        }
    }
}
