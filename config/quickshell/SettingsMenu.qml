import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

// Unified settings menu — Omarchy-style drilldown with categories:
//   Style    → Theme, Background, Keybinds
//   Setup    → Audio (wiremix), Bluetooth (bluetui), WiFi (impala),
//              Network (info), Language
//   System   → Lock, Suspend, Logout, Restart, Shutdown
//
// Each leaf is either an IPC call into an existing Quickshell
// overlay, a spawn of a floating-TUI window (Omarchy parity), or a
// system command.
//
// Trigger: `quickshell ipc call -- settings-menu toggle`
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    // Stack of node ids the user has drilled into. Empty = root.
    property var path: []

    readonly property color accent:     Theme.accent
    readonly property color background: Theme.cardBg
    readonly property color foreground: Theme.fg
    readonly property color foregroundDim: Theme.fgDim
    readonly property color border:     Theme.cardBorderColor
    readonly property int   cornerRadius: Theme.radius
    readonly property string fontFamily: Theme.monoFamily

    readonly property int contentMargin:  Theme.menuMargin
    readonly property int headerHeight:   Theme.menuHeaderHeight
    readonly property int contentSpacing: Theme.menuSpacing
    readonly property int rowSpacing:     Theme.menuRowSpacing
    readonly property int rowHeight:      Theme.menuRowHeight
    readonly property int cardWidth: 380
    readonly property int cardHeight: 540

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // ---- Menu tree --------------------------------------------------
    // Leaves have `action: function()`; branches have `children: [...]`.
    // `labelKey` is an I18n key; `icon` is an nf glyph.
    function _spawnTui(appId, cmd) {
        // Launches a foot window with a recognisable app-id so niri's
        // floating-TUI window-rule catches it (1000×640 centred).
        Quickshell.execDetached(["foot", "--app-id=tui-" + appId, cmd]);
    }
    function _ipc(target, fn) {
        // Defer the IPC call so the menu finishes closing first —
        // otherwise some overlays open behind our backdrop.
        Qt.callLater(() => Quickshell.execDetached([
            "quickshell", "ipc", "call", "--", target, fn || "toggle"
        ]));
    }

    readonly property var tree: ({
        "":         { children: ["style", "setup", "install", "remove", "system"] },
        "style":    { icon: "󰸌", labelKey: "settings.style",
                      children: ["style.theme", "style.background", "style.keybinds"] },
        "style.theme":      { icon: "󰸌", labelKey: "settings.style.theme",
                              action: () => root._ipc("theme-picker") },
        "style.background": { icon: "󰸀", labelKey: "settings.style.background",
                              action: () => root._ipc("background-picker") },
        "style.keybinds":   { icon: "󰌌", labelKey: "settings.style.keybinds",
                              action: () => root._ipc("keybind-sheet") },

        "setup":    { icon: "󰒓", labelKey: "settings.setup",
                      children: ["setup.audio", "setup.bluetooth", "setup.wifi",
                                 "setup.browser", "setup.language"] },
        "setup.audio":     { icon: "󰓃", labelKey: "settings.setup.audio",
                             action: () => root._spawnTui("wiremix", "wiremix") },
        "setup.bluetooth": { icon: "󰂯", labelKey: "settings.setup.bluetooth",
                             action: () => Quickshell.execDetached(["sh", "-lc",
                                 "rfkill unblock bluetooth; foot --app-id=tui-bluetui bluetui"]) },
        "setup.wifi":      { icon: "󰖩", labelKey: "settings.setup.wifi",
                             action: () => Quickshell.execDetached(["sh", "-lc",
                                 "rfkill unblock wifi 2>/dev/null; foot --app-id=tui-impala impala"]) },
        "setup.browser":   { icon: "󰖟", labelKey: "settings.setup.browser",
                             children: ["setup.browser.zen", "setup.browser.firefox",
                                        "setup.browser.chromium"] },
        "setup.browser.zen":      { icon: "󰖟", labelKey: "settings.setup.browser.zen",
                                    action: () => Quickshell.execDetached([
                                        Quickshell.env("HOME") + "/.local/bin/qs-default-browser-set", "zen"]) },
        "setup.browser.firefox":  { icon: "󰈹", labelKey: "settings.setup.browser.firefox",
                                    action: () => Quickshell.execDetached([
                                        Quickshell.env("HOME") + "/.local/bin/qs-default-browser-set", "firefox"]) },
        "setup.browser.chromium": { icon: "󰊯", labelKey: "settings.setup.browser.chromium",
                                    action: () => Quickshell.execDetached([
                                        Quickshell.env("HOME") + "/.local/bin/qs-default-browser-set", "chromium"]) },
        "setup.language":  { icon: "󰗊", labelKey: "settings.setup.language",
                             action: () => root._ipc("language-picker") },

        // Install / Remove: Omarchy parity. Their omarchy-menu surfaces
        // these as top-level branches; webapp install/remove are the
        // first leaves under each. Spawned in a floating foot (same
        // app-id pattern as the audio/bluetooth/wifi TUI launches
        // above) so the CLI walker is a one-shot dialog, not a
        // persistent terminal.
        "install":  { icon: "󰏗", labelKey: "settings.install",
                      children: ["install.webapp"] },
        "install.webapp": { icon: "󰖟", labelKey: "settings.install.webapp",
                            action: () => Quickshell.execDetached([
                                "foot", "--app-id=tui-qs-webapp-install",
                                Quickshell.env("HOME") + "/.local/bin/qs-webapp-install"]) },

        "remove":   { icon: "󰗨", labelKey: "settings.remove",
                      children: ["remove.webapp"] },
        "remove.webapp":  { icon: "󰖟", labelKey: "settings.remove.webapp",
                            action: () => Quickshell.execDetached([
                                "foot", "--app-id=tui-qs-webapp-remove",
                                Quickshell.env("HOME") + "/.local/bin/qs-webapp-remove"]) },

        "system":   { icon: "󰐥", labelKey: "settings.system",
                      children: ["system.lock", "system.suspend", "system.logout",
                                 "system.restart", "system.shutdown"] },
        "system.lock":     { icon: "󰌾", labelKey: "power.action.lock",
                             action: () => Quickshell.execDetached([
                                 "quickshell", "-p",
                                 Quickshell.env("HOME") + "/.config/quickshell/lock/shell.qml"]) },
        "system.suspend":  { icon: "󰒲", labelKey: "power.action.suspend",
                             action: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        "system.logout":   { icon: "󰍃", labelKey: "power.action.logout",
                             action: () => Quickshell.execDetached([
                                 "niri", "msg", "action", "quit", "--skip-confirmation"]) },
        "system.restart":  { icon: "󰜉", labelKey: "power.action.restart",
                             action: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        "system.shutdown": { icon: "󰐥", labelKey: "power.action.shutdown",
                             action: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
    })

    function _currentNode() {
        return tree[path.length > 0 ? path[path.length - 1] : ""];
    }

    function _label(id) {
        const n = tree[id];
        return n && n.labelKey ? I18n.t(n.labelKey) : id;
    }

    function _breadcrumb() {
        const parts = [I18n.t("settings.placeholder")];
        for (let i = 0; i < path.length; i++) parts.push(_label(path[i]));
        return parts.join(" › ");
    }

    // ---- Open / close / drilldown ----------------------------------
    function open() {
        opened = true;
        filterText = "";
        path = [];
        selectedIndex = 0;
        rebuild();
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }
    function closeMenu()  { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function _enterChild(childId) {
        path = path.concat([childId]);
        filterText = "";
        selectedIndex = 0;
        rebuild();
    }
    function _pop() {
        if (path.length === 0) { closeMenu(); return; }
        path = path.slice(0, path.length - 1);
        filterText = "";
        selectedIndex = 0;
        rebuild();
    }

    function rebuild() {
        displayModel.clear();
        const node = _currentNode();
        const kids = (node && node.children) ? node.children : [];
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < kids.length; i++) {
            const id = kids[i];
            const n = tree[id];
            if (!n) continue;
            const label = _label(id);
            if (q && label.toLowerCase().indexOf(q) < 0 &&
                    id.toLowerCase().indexOf(q) < 0) continue;
            displayModel.append({
                id: id,
                icon: n.icon || "",
                label: label,
                isBranch: !!n.children,
                index: displayModel.count
            });
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
        const item = displayModel.get(idx);
        const node = tree[item.id];
        if (!node) return;
        if (node.children) {
            _enterChild(item.id);
        } else if (node.action) {
            closeMenu();
            node.action();
        }
    }

    ListModel { id: displayModel }

    IpcHandler {
        target: "settings-menu"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closeMenu(); return "ok" }
        function toggle(): string { root.toggleMenu(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "qs-settings-menu"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closeMenu()

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        if (root.filterText)        root.setFilter("");
                        else                        root._pop();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (root.filterText.length > 0)
                            root.setFilter(root.filterText.slice(0, -1));
                        else
                            root._pop();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.select(-1); event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.select(1); event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        // Drill back up one level.
                        root._pop(); event.accepted = true;
                    } else if (event.key === Qt.Key_Right ||
                               event.key === Qt.Key_Return ||
                               event.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex);
                        event.accepted = true;
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

                // Header — breadcrumb when not filtering, filter text otherwise.
                Item {
                    width: parent.width
                    height: root.headerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || root._breadcrumb()
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.78
                        font.family: root.fontFamily
                        font.pixelSize: Theme.menuFontPx
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: rowList
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing
                    model: displayModel
                    clip: true
                    spacing: root.rowSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string id
                        required property string icon
                        required property string label
                        required property bool isBranch
                        readonly property bool selected: index === root.selectedIndex

                        width: ListView.view.width
                        height: root.rowHeight
                        radius: root.cornerRadius
                        color: row.selected
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
                                text: row.icon
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuIconPx
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22 - 14 - (row.isBranch ? 18 : 0)
                                text: row.label
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuFontPx
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: row.isBranch
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                color: row.selected ? root.accent : root.foregroundDim
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuFontPx
                                width: 18
                                horizontalAlignment: Text.AlignRight
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
