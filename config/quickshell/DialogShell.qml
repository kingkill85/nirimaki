import QtQuick
import Quickshell
import Quickshell.Wayland

// Shared two-surface dialog wrapper. Used by every full-screen
// quickshell popup (Launcher, PowerMenu, ClipboardPicker, …) so
// niri's compositor blur is scoped to the card's geometry only,
// not the entire scrim. Pre-refactor each dialog was a single
// full-screen layer surface with a translucent scrim child, which
// caused niri's `background-effect blur` (matched on `qs-*`) to
// blur the entire screen behind the dialog — not the Omarchy look.
//
// Now we host two layer surfaces:
//   - scrim  (namespace `qs-scrim`, full-screen, NOT matched by
//     niri's blur layer-rule)
//   - dialog (namespace `qs-<name>`, sized to card, IS matched and
//     gets compositor blur behind its translucent body)
//
// Both anchor `exclusiveZone: 0` so they sit below the bar's
// exclusive zone — fixes the inconsistency where some dialogs used
// `exclusionMode: ExclusionMode.Ignore` and blurred over the bar
// while Launcher (which already used `exclusiveZone: 0`) did not.
Item {
    id: shell
    visible: false  // never visible itself, only hosts PanelWindows

    // ---- Public API ----
    property bool open: false
    // Scrim is invisible by default — matching Omarchy's walker, where
    // dialogs float with a blurred backdrop only behind the card and
    // the rest of the desktop stays sharp + un-dimmed. The scrim still
    // exists as a full-screen layer surface so it can catch clicks
    // outside the card and dismiss the dialog. Per-dialog overrides
    // are accepted but discouraged.
    property color scrimColor: "transparent"
    property string dialogNamespace: "qs-dialog"
    property int cardWidth: 400
    property int cardHeight: 300
    property color cardColor: Theme.cardBg
    property color cardBorderColor: Theme.cardBorderColor
    property int cardBorderWidth: Theme.cardBorderWidth
    property int cardRadius: Theme.radius

    signal closeRequested

    // Children declared inside <DialogShell> { ... } land inside the
    // dialog card's interior (after the card's border + radius).
    default property alias content: cardContents.data

    // ---- Scrim surface (full-screen, no blur, click-to-close) ----
    PanelWindow {
        id: scrimWin
        visible: shell.open
        anchors { top: true; bottom: true; left: true; right: true }
        color: shell.scrimColor
        // Namespace is intentionally outside the `qs-*` family so
        // niri's blur layer-rule (which matches `^(quickshell|qs-.*)$`)
        // does NOT apply blur to the scrim. Only the dialog surface
        // gets blur.
        WlrLayershell.namespace: "nirimaki-scrim"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: 0

        MouseArea {
            anchors.fill: parent
            onClicked: shell.closeRequested()
        }
    }

    // ---- Dialog surface (sized to card, blur applies) ----
    PanelWindow {
        id: dialogWin
        visible: shell.open
        // Anchor to top-left and center via computed margins.
        // Layer-shell positioning needs an anchored edge to bind to.
        anchors { top: true; left: true }
        margins {
            top: dialogWin.screen
                ? Math.max(0, Math.round((dialogWin.screen.height - shell.cardHeight) / 2))
                : 0
            left: dialogWin.screen
                ? Math.max(0, Math.round((dialogWin.screen.width - shell.cardWidth) / 2))
                : 0
        }
        implicitWidth: shell.cardWidth
        implicitHeight: shell.cardHeight
        color: "transparent"
        WlrLayershell.namespace: shell.dialogNamespace
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.exclusiveZone: 0

        Rectangle {
            anchors.fill: parent
            color: shell.cardColor
            border.color: shell.cardBorderColor
            border.width: shell.cardBorderWidth
            radius: shell.cardRadius

            // Swallow clicks on the card body so they don't fall
            // through to the scrim's click-to-close MouseArea.
            MouseArea { anchors.fill: parent }

            Item {
                id: cardContents
                anchors.fill: parent
            }
        }
    }
}
