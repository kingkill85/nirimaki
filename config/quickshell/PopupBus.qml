pragma Singleton
import QtQuick

// Single-popup gate for bar widgets AND full-screen overlays.
//
// Bar widgets expose `popupOpen: bool` on their root Item; full-screen
// overlays (Launcher, EmojiPicker, ClipboardPicker, …) expose `opened`.
// In either case the widget calls
//     PopupBus.show(root)
// when it opens, and PopupBus clears whichever flag the previously-
// open peer used. We can't just flip `popup.visible = false` because
// the visibility is binding-driven; we have to write back to the
// source property.
//
// The bus treats bar popups and overlays uniformly — opening any one
// dismisses any other. That keeps the user from accidentally stacking
// (e.g. the Launcher over the Calendar dropdown).
QtObject {
    id: bus

    // Root Item of the currently-open widget (or null).
    property var current: null

    function _close(it) {
        if (!it) return;
        // Overlays use `opened`; bar popups use `popupOpen`. Closing
        // is just writing false to whichever the peer happens to use.
        if (it.opened !== undefined)        it.opened = false;
        else if (it.popupOpen !== undefined) it.popupOpen = false;
    }

    function show(owner) {
        if (current && current !== owner) _close(current);
        current = owner;
    }

    function hide(owner) {
        if (current === owner) current = null;
    }
}
