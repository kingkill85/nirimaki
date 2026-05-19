import QtQuick
import Quickshell.Wayland

// Focused-window title.
// Uses wlr-foreign-toplevel-management (compositor-agnostic) — same code
// Omarchy uses on Hyprland.
//   Left click  → niri maximize-column (fills workspace area, bar stays visible)
//   Middle/Right click → close the window
Item {
    id: root

    property int maxWidth: 280

    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string title:
        toplevel ? (toplevel.title || toplevel.appId || "") : ""

    visible: title !== ""
    // Measure text via TextMetrics — independent of layout, so no binding loop.
    implicitWidth: visible
        ? Math.min(maxWidth, titleMetrics.width) + 16
        : 0
    implicitHeight: Theme.barHeight

    TextMetrics {
        id: titleMetrics
        text: root.title
        font.family: Theme.sansFamily
        font.pixelSize: Theme.fontPx
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.title
            color: Theme.fg
            font.family: Theme.sansFamily
            font.pixelSize: Theme.fontPx
            elide: Text.ElideRight
            opacity: 0.85
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (!root.toplevel) return;
            if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) {
                root.toplevel.close();
            } else {
                NiriService.runAction("maximize-column");
            }
        }
    }
}
