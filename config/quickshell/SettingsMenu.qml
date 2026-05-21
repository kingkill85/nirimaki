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
    // Loaded from config/quickshell/settings-menu.json + merged with the
    // user's ~/.config/nirimaki/extensions/menu.json (entries with the
    // same id override; new ids extend). Schema documented at the top
    // of the JSON file.
    property var tree: ({})

    // Replace $HOME tokens inside any string within an action payload.
    function _expandHome(v) {
        if (typeof v === "string")
            return v.split("$HOME").join(Quickshell.env("HOME"));
        if (Array.isArray(v))
            return v.map(root._expandHome);
        return v;
    }

    // Dispatcher: map { type, ... } action records to the right runtime
    // call. Types mirror the schema documented in settings-menu.json.
    function _dispatch(action) {
        if (!action || !action.type) return;
        const a = action;
        if (a.type === "ipc") {
            // Defer the IPC call so the menu finishes closing first —
            // otherwise some overlays open behind our backdrop.
            const target = a.target, fn = a.fn || "toggle";
            Qt.callLater(() => Quickshell.execDetached([
                "quickshell", "ipc", "call", "--", target, fn]));
        } else if (a.type === "tui") {
            NiriService.launchTui.apply(null, [a.name].concat((a.exec || []).map(root._expandHome)));
        } else if (a.type === "shell") {
            Quickshell.execDetached(["sh", "-lc", root._expandHome(a.cmd)]);
        } else if (a.type === "exec") {
            Quickshell.execDetached((a.cmd || []).map(root._expandHome));
        } else if (a.type === "exec-in-foot") {
            const argv = ["foot", "--app-id=" + a.appId].concat(
                (a.cmd || []).map(root._expandHome));
            Quickshell.execDetached(argv);
        } else if (a.type === "quickshell-spawn") {
            Quickshell.execDetached(["quickshell", "-p", root._expandHome(a.path)]);
        } else {
            console.warn("SettingsMenu: unknown action type:", a.type);
        }
    }

    // Merge `extra` (user JSON) on top of `base` (shipped JSON), per-key.
    // Each menu id is a top-level key. If the user redefines an id, the
    // user's fields fully replace the shipped node (no deep merge of
    // children arrays — too clever, would surprise on override).
    function _mergeTrees(base, extra) {
        const out = {};
        for (const k in base)  out[k] = base[k];
        for (const k in extra) {
            if (k === "_comment") continue;
            out[k] = extra[k];
        }
        return out;
    }

    function _loadTreeJson(raw, source) {
        if (!raw) return null;
        try {
            const parsed = JSON.parse(raw);
            // Strip the _comment key for sanity (it's documentation only).
            delete parsed._comment;
            return parsed;
        } catch (e) {
            console.warn("SettingsMenu: failed to parse " + source + ":", e.toString());
            return null;
        }
    }

    property var _defaultTree: ({})
    property var _userTree: ({})

    function _rebuildTree() {
        root.tree = root._mergeTrees(root._defaultTree, root._userTree);
        if (root.opened) root.rebuild();
    }

    property FileView _defaultTreeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/settings-menu.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = root._loadTreeJson(text(), "settings-menu.json");
            if (t) { root._defaultTree = t; root._rebuildTree(); }
        }
        onFileChanged: reload()
    }

    property FileView _userTreeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/nirimaki/extensions/menu.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = root._loadTreeJson(text(), "extensions/menu.json");
            root._userTree = t || ({});
            root._rebuildTree();
        }
        onFileChanged: reload()
        onLoadFailed: { root._userTree = ({}); root._rebuildTree(); }
    }

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
            _dispatch(node.action);
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
        dialogNamespace: "nirimaki-settings-menu"
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
