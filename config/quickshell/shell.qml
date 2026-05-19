//@ pragma UseQApplication
import Quickshell
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

    // Notification toast stack — one per screen.
    Variants {
        model: Quickshell.screens
        delegate: NotificationToast {}
    }

    // Single Launcher (overlay, IPC-triggered).
    Launcher {}

    // OSD bezel for volume / mute / brightness. IPC-driven; see bin/qs-osd.
    Osd {}

    // Clipboard history picker. IPC-triggered (Mod+Period).
    ClipboardPicker {}

    // Power / session menu (Lock / Suspend / Logout / Restart / Shutdown).
    PowerMenu {}

    // Emoji picker. IPC-triggered (Mod+E).
    EmojiPicker {}

    // Theme picker — pick an entry under ~/.config/theme/themes/ and
    // apply via qs-theme-set. IPC-triggered (Mod+Shift+T).
    ThemePicker {}

    // Background picker — grid of images under the current theme's
    // backgrounds/. Writes a symlink + restarts swaybg via
    // qs-wallpaper-apply. IPC-triggered (Mod+Shift+B).
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
