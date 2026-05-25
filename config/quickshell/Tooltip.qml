import QtQuick

// Small contextual label that appears after the cursor dwells on a
// `target` Item. Stays in-scene (no PopupWindow) so it lives inside
// the same surface as its target — fine for bar widgets, panels,
// and popovers alike, just not bar pills (those need a PopupWindow
// to escape the bar's vertical extent; BarPill.tooltipText handles
// that case).
//
//   Item {
//       Text { id: chip; ... }
//       Tooltip { target: chip; text: "Battery: 78 %" }
//   }
Rectangle {
    id: root

    property Item   target: null
    property string text: ""
    property int    delayMs: Theme.tooltipDelay
    // Position relative to target: "below" (default) | "above" | "right" | "left".
    property string position: "below"

    visible: false
    z: 1000
    radius: Theme.radius
    color: Theme.cardBg
    border.color: Theme.cardBorderColor
    border.width: 1
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 100 } }

    implicitWidth:  label.implicitWidth + 2 * Theme.tooltipPadX
    implicitHeight: label.implicitHeight + 2 * Theme.tooltipPadY

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: Theme.fg
        font.family: Theme.sansFamily
        font.pixelSize: Theme.tooltipFontPx
    }

    function _reposition() {
        if (!target) return;
        const t = target;
        const gap = 6;
        const p = t.mapToItem(root.parent, 0, 0);
        if (root.position === "above") {
            root.x = p.x + (t.width  - root.width)  / 2;
            root.y = p.y - root.height - gap;
        } else if (root.position === "right") {
            root.x = p.x + t.width + gap;
            root.y = p.y + (t.height - root.height) / 2;
        } else if (root.position === "left") {
            root.x = p.x - root.width - gap;
            root.y = p.y + (t.height - root.height) / 2;
        } else {
            root.x = p.x + (t.width  - root.width)  / 2;
            root.y = p.y + t.height + gap;
        }
    }
    onTargetChanged: _reposition()
    onTextChanged:   _reposition()
    onWidthChanged:  _reposition()
    onHeightChanged: _reposition()

    Timer {
        id: showTimer
        interval: root.delayMs
        onTriggered: {
            if (!hover.hovered) return;
            root._reposition();
            root.visible = true;
            root.opacity = 1;
        }
    }

    HoverHandler {
        id: hover
        target: root.target
        onHoveredChanged: {
            if (hovered) showTimer.restart();
            else {
                showTimer.stop();
                root.opacity = 0;
                Qt.callLater(() => { if (!hover.hovered) root.visible = false; });
            }
        }
    }
}
