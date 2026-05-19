pragma Singleton
import QtQuick

// Single-popup gate for bar widgets. Each bar widget exposes a
// `popupOpen: bool` on its root Item; the popup's `visible` is bound
// to that property. When a popup opens it calls
//     PopupBus.show(root)
// and PopupBus clears the previously-open widget's `popupOpen`. We
// can't just flip `popup.visible = false` because every popup is
// driven by a `visible: root.popupOpen` binding — setting `visible`
// would either break the binding or get overridden by the next
// re-evaluation. Touching the source property is what actually
// propagates.
QtObject {
    id: bus

    // Root Item of the currently-open bar popup (or null).
    property var current: null

    function show(owner) {
        if (current && current !== owner) current.popupOpen = false;
        current = owner;
    }

    function hide(owner) {
        if (current === owner) current = null;
    }
}
