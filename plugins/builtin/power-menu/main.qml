import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs

// Power / session menu. Visually styled after Omarchy's
// shell/plugins/menu/Menu.qml (same 300px card, walker-style action list,
// JetBrainsMono Nerd Font icons) but with hardcoded power actions only.
// Icons + labels match the `system.*` entries in Omarchy's
// default/omarchy/omarchy-menu.jsonc.
//
// A full port of Omarchy's generic menu system (JSONC-driven, drilldowns,
// providers) is a much larger task — deferred. This file gives us the
// Phase C "Power menu" item: lock / suspend / logout / restart / shutdown.
//
// Trigger: `quickshell ipc call -- power-menu toggle` (bound to Mod+Shift+E
// in niri config — replaces the default niri quit-confirmation dialog).
Item {
    id: root

    // Action labels are looked up via I18n.t() at render time (in the
    // row delegate below), not stored here — that way switching locale
    // re-tints labels without re-building `actions`.
    readonly property var actions: [
        { id: "lock",     icon: "󰌾", labelKey: "power.action.lock",     cmd: ["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell/lock/shell.qml"] },
        { id: "suspend",  icon: "󰒲", labelKey: "power.action.suspend",  cmd: ["systemctl", "suspend"] },
        { id: "logout",   icon: "󰍃", labelKey: "power.action.logout",   cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"] },
        { id: "restart",  icon: "󰜉", labelKey: "power.action.restart",  cmd: ["systemctl", "reboot"] },
        { id: "shutdown", icon: "󰐥", labelKey: "power.action.shutdown", cmd: ["systemctl", "poweroff"] }
    ]

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0

    // Latched once the menu has been opened — keeps the lazy-loaded
    // content tree alive after first close so re-opens are instant.
    property bool _everLoaded: false
    onOpenedChanged: {
        if (opened) {
            _everLoaded = true;
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
        }
    }

    readonly property color accent:     Theme.accent
    readonly property color background: Theme.cardBg
    readonly property color foreground: Theme.fg
    readonly property color border:     Theme.cardBorderColor
    readonly property int cornerRadius: Theme.radius
    readonly property string fontFamily: Theme.monoFamily
    // All menu sizing comes from Theme so PowerMenu / EmojiPicker /
    // ClipboardPicker / Launcher render identically. Per-overlay
    // size differences (card width) stay local.
    readonly property int contentMargin:  Theme.menuMargin
    readonly property int headerHeight:   Theme.menuHeaderHeight
    readonly property int contentSpacing: Theme.menuSpacing
    readonly property int rowSpacing:     Theme.menuRowSpacing
    readonly property int rowHeight:      Theme.menuRowHeight
    readonly property int cardWidth: 300
    readonly property int cardHeight:
        contentMargin * 2 + headerHeight + contentSpacing +
        (displayModel.count > 0
            ? displayModel.count * rowHeight + (displayModel.count - 1) * rowSpacing
            : rowHeight)

    function open() {
        opened = true;
        filterText = "";
        selectedIndex = 0;
        rebuild();
        // Focus is grabbed inside the content Component via Connections
        // on root.opened — see Loader below.
    }
    function closeMenu() { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function rebuild() {
        displayModel.clear();
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < actions.length; i++) {
            const a = actions[i];
            const label = I18n.t(a.labelKey);
            if (!q ||
                label.toLowerCase().indexOf(q) >= 0 ||
                a.id.indexOf(q) >= 0) {
                displayModel.append({
                    actionId: a.id,
                    icon: a.icon,
                    labelKey: a.labelKey,
                    index: displayModel.count
                });
            }
        }
        if (displayModel.count === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
    }

    function select(delta) {
        if (displayModel.count === 0) return;
        selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        rebuild();
    }

    function activate(idx) {
        if (idx < 0 || idx >= displayModel.count) return;
        const id = displayModel.get(idx).actionId;
        let cmd = null;
        for (let i = 0; i < actions.length; i++) {
            if (actions[i].id === id) { cmd = actions[i].cmd; break; }
        }
        if (!cmd) return;
        closeMenu();
        Quickshell.execDetached(cmd);
    }

    ListModel { id: displayModel }

    IpcHandler {
        target: "power-menu"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closeMenu(); return "ok" }
        function toggle(): string { root.toggleMenu(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-power-menu"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closeMenu()

        // Lazy-load the menu's interior — the Item + Column + ListView
        // tree only instantiates on first open, and stays loaded for
        // subsequent opens. The bar itself doesn't pay this cost at
        // shell startup.
        Loader {
            anchors.fill: parent
            active: root.opened || root._everLoaded
            sourceComponent: contentComponent
        }

        Component {
            id: contentComponent

        Item {
            anchors.fill: parent

            // Grab focus when the dialog opens. Fires on first load
            // (Component.onCompleted) and on every subsequent open
            // (Connections on root.opened).
            Component.onCompleted: Qt.callLater(() => keyCatcher.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => keyCatcher.forceActiveFocus());
                }
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        if (root.filterText) root.setFilter("");
                        else root.closeMenu();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1));
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.select(-1); event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.select(1); event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex); event.accepted = true;
                    } else if (event.text && event.text.length === 1 &&
                               event.text.charCodeAt(0) >= 32 &&
                               event.text.charCodeAt(0) !== 127) {
                        root.setFilter(root.filterText + event.text);
                        event.accepted = true;
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: root.contentMargin
                spacing: root.contentSpacing

                // Search header (only shows the filter / placeholder).
                Rectangle {
                    width: parent.width
                    height: root.headerHeight
                    color: "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || I18n.t("power.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
                        font.family: root.fontFamily
                        font.pixelSize: Theme.fontPxLarge
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: rowList
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing
                    model: displayModel
                    interactive: false
                    spacing: root.rowSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property int index
                        required property string actionId
                        required property string icon
                        required property string labelKey

                        width: ListView.view.width
                        height: root.rowHeight
                        radius: root.cornerRadius
                        color: index === root.selectedIndex
                               ? root.withAlpha(root.foreground, 0.08)
                               : root.withAlpha(root.foreground,
                                                mouseArea.containsMouse ? 0.045 : 0)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 14

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.icon
                                color: index === root.selectedIndex
                                       ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuIconPx
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t(parent.parent.labelKey)
                                color: index === root.selectedIndex
                                       ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuFontPx
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index;
                                root.activate(index);
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
