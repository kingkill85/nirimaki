import QtQuick
import Quickshell
import qs

// Uniform bar-widget popover: transparent PopupWindow anchored under
// a BarPill, with the standard `Theme.cardBg` bordered card, an
// Escape-catching focus item, PopupBus participation (opening any
// popover dismisses the previously-open peer), and popupX recompute
// on every show (mapToItem isn't binding-reactive).
//
// Usage:
//
//   BarPill { id: pill; active: popover.popupOpen; onClicked: popover.toggle() }
//
//   BarPopover {
//       id: popover
//       barWindow:  root.barWindow
//       anchorItem: pill
//       implicitWidth:  280
//       implicitHeight: content.implicitHeight + 2 * contentMargin
//
//       Column { id: content; ... }
//   }
//
// Default-property children land inside the card with `contentMargin`
// padding applied; consumers size the popover via implicitWidth /
// implicitHeight directly on BarPopover.
PopupWindow {
    id: root

    required property var barWindow
    required property var anchorItem

    // PopupBus writes to `popupOpen` on close, so this name is load-bearing.
    property bool popupOpen: false

    // Inner padding between card border and consumer content.
    property int contentMargin: 12

    default property alias content: contentArea.data

    color: "transparent"
    visible: popupOpen

    function open()   { popupOpen = true; }
    function close()  { popupOpen = false; }
    function toggle() { popupOpen = !popupOpen; }

    // popupX is recomputed on every show — mapToItem isn't binding-
    // reactive, so a bound value would freeze at construction time
    // (before the bar has laid out) and place the popover wrong.
    property real popupX: 0
    anchor.window: barWindow
    anchor.rect.x: popupX
    anchor.rect.y: barWindow ? barWindow.height : 0

    onVisibleChanged: {
        if (visible) {
            popupX = anchorItem.mapToItem(barWindow.contentItem, 0, 0).x
                   + (anchorItem.width - implicitWidth) / 2;
            PopupBus.show(root);
            Qt.callLater(() => keyCatcher.forceActiveFocus());
        } else {
            PopupBus.hide(root);
            // Compositor-driven dismiss (click-outside) leaves
            // popupOpen=true on the next frame; sync it back.
            if (popupOpen) popupOpen = false;
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.popupOpen = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.cardBg
        border.color: Theme.cardBorderColor
        border.width: Theme.cardBorderWidth
    }

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: root.contentMargin
    }
}
