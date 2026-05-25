import QtQuick

// Footer row of equally-sized PopoverButtons inside a BarPopover.
//
//   PopoverActions {
//       PopoverButton { label: "turn off";  onTriggered: ... }
//       PopoverButton { label: "bluetui";   variant: PopoverButton.Primary; onTriggered: ... }
//   }
//
// Children laid out left-to-right, each one taking an equal share of
// the row width minus inter-button gaps. Pure presentation — buttons
// own their own click handling.
Row {
    id: root

    width: parent ? parent.width : 0
    spacing: Theme.popoverButtonSpacing

    onChildrenChanged: relayout()
    onWidthChanged:    relayout()
    Component.onCompleted: relayout()

    function relayout() {
        const n = children.length;
        if (n === 0) return;
        const each = (width - spacing * (n - 1)) / n;
        for (let i = 0; i < n; i++) {
            const c = children[i];
            if (c && c.width !== undefined) c.width = each;
        }
    }
}
