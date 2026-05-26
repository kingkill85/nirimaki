import QtQuick

// Footer row of equally-sized PopoverButtons inside a BarPopover.
//
//   PopoverActions {
//       PopoverButton { label: "turn off"; onTriggered: ... }
//       PopoverButton { label: "manage";   variant: PopoverButton.Primary; onTriggered: ... }
//   }
//
// Children laid out left-to-right, each one taking an equal share of
// the row width minus inter-button gaps. Pure presentation — buttons
// own their own click handling.
Row {
    id: root

    width: parent ? parent.width : 0
    spacing: Theme.popoverButtonSpacing

    onChildrenChanged: { _rewire(); relayout(); }
    onWidthChanged:    relayout()
    Component.onCompleted: { _rewire(); relayout(); }

    // Only allocate width to visible children — hidden buttons would
    // otherwise still claim a column slot, leaving the lone visible
    // button at half-width on widgets that conditionally render one
    // action (e.g. the network popover on a wired-only box).
    function relayout() {
        const vis = [];
        for (const c of children) {
            if (c && c.visible && c.width !== undefined) vis.push(c);
        }
        if (vis.length === 0) return;
        const each = (width - spacing * (vis.length - 1)) / vis.length;
        for (const c of vis) c.width = each;
    }

    // Watch each child's `visibleChanged` so flipping a button on/off
    // re-distributes the row. Without this, the visible-child set is
    // only re-read when the children array itself mutates. The Set
    // dedupes — QML can re-run onChildrenChanged on the same set.
    property var _wired: new Set()
    function _rewire() {
        for (const c of children) {
            if (!c || !c.visibleChanged) continue;
            if (_wired.has(c)) continue;
            _wired.add(c);
            c.visibleChanged.connect(relayout);
        }
    }
}
