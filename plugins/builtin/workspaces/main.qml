import QtQuick
import QtQuick.Layouts
import qs

// Workspaces indicator for a given niri output. Omarchy-style: flat
// glyphs, no pills — the visible workspace on this output shows a dot
// (󱓻), the rest show their number, and empty workspaces dim out.
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

            delegate: Item {
                required property var modelData
                // `is_active` = visible on this output, `is_focused` =
                // globally focused. The dot marks the visible one; accent
                // tints it only on the focused monitor. Empty = no window.
                readonly property bool here:  modelData.is_active
                readonly property bool empty: !modelData.active_window_id

                implicitWidth:  Math.max(label.implicitWidth + Theme.padX, 12)
                implicitHeight: Theme.barHeight - 2 * Theme.padY

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: parent.here
                          ? "󱓻"                       // nf-md-circle (active marker)
                          : (modelData.name && modelData.name.length
                             ? modelData.name
                             : String(modelData.idx))
                    color: modelData.is_focused ? Theme.accent : Theme.fg
                    opacity: parent.here ? 1.0 : (parent.empty ? 0.4 : 0.85)
                    font.family: parent.here ? Theme.iconFamily : Theme.sansFamily
                    font.pixelSize: Theme.barFontPx
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
