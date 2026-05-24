//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    // QML singletons are lazy-loaded — they don't instantiate until
    // something references a property on them. The I18n singleton's
    // IpcHandler won't register until then. A throwaway QtObject
    // bound to a property of the singleton forces instantiation at
    // shell startup; once F3 wires `I18n.t(...)` into every widget
    // this becomes redundant but harmless.
    QtObject { property string _eager: I18n.locale }

    // One Bar per screen.
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // Click-outside scrim for bar popups (Calendar / Weather / Network /
    // Media dropdowns). Quickshell's PopupWindow on niri isn't a grabbed
    // xdg_popup, so the compositor doesn't auto-dismiss it on outside
    // interaction — we host a transparent layer surface that catches
    // clicks anywhere outside the popup card and clears PopupBus.current.
    //
    // Margined down by the bar's exclusive zone so the bar pill itself
    // stays clickable (so toggling the same pill closes the popup).
    // Overlay-style full-screen dialogs (Launcher, EmojiPicker, …) have
    // their own DialogShell scrim and use `opened`; this scrim is gated
    // on `popupOpen` so it only applies to bar widgets.
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: PopupBus.current !== null
                     && PopupBus.current.popupOpen === true
            anchors { top: true; bottom: true; left: true; right: true }
            margins { top: Theme.barHeight }
            color: "transparent"
            // Namespace intentionally outside the `nirimaki-*` family so
            // niri's blur layer-rule (matches `^(quickshell|nirimaki-.*)$`)
            // does NOT apply compositor blur to the transparent scrim —
            // same approach as DialogShell's `dialog-scrim`.
            WlrLayershell.namespace: "bar-popup-scrim"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (PopupBus.current && PopupBus.current.popupOpen === true)
                        PopupBus.current.popupOpen = false;
                }
            }
        }
    }

    // Notification toast stack — one per screen.
    Variants {
        model: Quickshell.screens
        delegate: NotificationToast {}
    }

    // Single Launcher (overlay, IPC-triggered).
    Launcher {}

    // OSD bezel for volume / mute / brightness. IPC-driven; see bin/nirimaki-osd.
    Osd {}

    // Clipboard history picker. IPC-triggered (Mod+Period).
    ClipboardPicker {}

    // Power / session menu (Lock / Suspend / Logout / Restart / Shutdown).
    PowerMenu {}

    // Emoji picker. IPC-triggered (Mod+E).
    EmojiPicker {}

    // Theme picker — pick an entry under ~/.config/theme/themes/ and
    // apply via nirimaki-theme-set. IPC-triggered (Mod+Shift+T).
    ThemePicker {}

    // Background picker — grid of images under the current theme's
    // backgrounds/. Writes a symlink + restarts swaybg via
    // nirimaki-wallpaper-apply. IPC-triggered (Mod+Shift+B).
    BackgroundPicker {}

    // Keybind cheat sheet — parses keybinds.kdl + shows every bind
    // grouped by section. IPC-triggered (F1 / Mod+Shift+/).
    KeybindSheet {}

    // Unified settings menu — Omarchy-style drilldown over Style /
    // Setup / System. IPC-triggered (Mod+Alt+Space).
    SettingsMenu {}

    // Language picker. Writes ~/.config/quickshell/locale; I18n
    // singleton picks that up first when resolving the active locale.
    // Reachable via Settings → Setup → Language.
    LanguagePicker {}
}
