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

    // One Bar per screen. Bar widgets are plugins (see plugins/builtin/);
    // shell.qml just provides the per-screen Bar host.
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

    // ---- Plugin hosts ----
    // Three top-level mount surfaces; the loader instantiates whichever
    // plugins are configured + installed for each mount type. Overlays
    // are full-screen IPC-triggered dialogs (Launcher, PowerMenu, …),
    // bezels are transient OSD-style overlays, toasts are per-screen
    // passive surfaces. Each plugin's main.qml owns its own scrim,
    // DialogShell, Variants-per-screen as appropriate.

    Variants {
        model: Plugins.byMount["overlay"] || []
        delegate: Loader {
            required property var modelData
            active: true
            source: Plugins.entryUrl(modelData)
        }
    }

    Variants {
        model: Plugins.byMount["bezel"] || []
        delegate: Loader {
            required property var modelData
            active: true
            source: Plugins.entryUrl(modelData)
        }
    }

    Variants {
        model: Plugins.byMount["toast"] || []
        delegate: Loader {
            required property var modelData
            active: true
            source: Plugins.entryUrl(modelData)
        }
    }
}
