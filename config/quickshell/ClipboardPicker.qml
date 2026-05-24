import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Clipboard history picker — ported from Omarchy's
// shell/plugins/clipboard-picker/ClipboardPicker.qml (omarchy-shell branch).
//
// Backend swap: Omarchy uses their "elephant" tool + wtype. We use cliphist
// (extra/cliphist) + wtype + wl-copy:
//   - fetch:     `cliphist list`  →  "<id>\t<preview>" lines
//   - activate:  `cliphist decode <id> | wl-copy`, then wtype Shift+Insert
//                pastes into the focused window
// The clipboard daemon (`wl-paste --watch cliphist store`) is started by
// niri at session start — see config.kdl `spawn-sh-at-startup`.
//
// Theming adapted: qs.Commons (Color.menu.*, Style.cornerRadius, env
// OMARCHY_MENU_FONT) → Theme.qml.
//
// Trigger: `quickshell ipc call -- clipboard-picker toggle`
// (bound to Mod+Period in niri config).
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property var items: []

    // Latched once the picker has been opened — keeps the lazy-loaded
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
    readonly property int contentMargin:  Theme.menuMargin
    readonly property int headerHeight:   Theme.menuHeaderHeight
    readonly property int contentSpacing: Theme.menuSpacing
    readonly property int cardWidth: 800
    readonly property int cardHeight: 600
    readonly property int rowHeight:      Theme.menuRowHeight

    function open() {
        opened = true;
        filterText = "";
        selectedIndex = 0;
        fetchProc.collected = "";
        fetchProc.command = ["cliphist", "list"];
        fetchProc.running = true;
        // Focus is grabbed inside the content Component via Connections
        // on root.opened — see Loader below.
    }

    function closePicker() { opened = false; }

    function togglePicker() { opened ? closePicker() : open(); }

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function rebuildDisplay() {
        const query = filterText.trim().toLowerCase();
        displayModel.clear();
        let outCount = 0;
        for (let i = 0; i < items.length; i++) {
            const entry = items[i];
            const isImage = entry.preview_type === "image";
            const textMatch = !isImage && entry.preview &&
                              entry.preview.toLowerCase().indexOf(query) >= 0;
            if (!query || textMatch) {
                displayModel.append({
                    identifier: entry.identifier,
                    previewText: isImage ? "" : entry.preview.replace(/\n/g, " "),
                    previewType: isImage ? "image" : "text",
                    index: outCount
                });
                outCount++;
                if (outCount >= 50) break;
            }
        }
        if (displayModel.count === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
        Qt.callLater(() => {
            if (contentLoader.item && displayModel.count > 0)
                contentLoader.item.scrollToSelected();
        });
    }

    // positionViewAtIndex on selectedIndex change is wired up via
    // Connections inside the content Component below.
    function select(delta) {
        if (displayModel.count === 0) return;
        selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        rebuildDisplay();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= displayModel.count) return;
        applySelected(displayModel.get(idx).identifier);
    }

    function applySelected(identifier) {
        if (!identifier) return;
        opened = false;
        // `cliphist list` lines begin with a numeric id followed by a tab.
        // Re-quote via single-quote-escaping (defensive though cliphist ids
        // are integers).
        const safe = String(identifier).replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-lc",
            "cliphist decode '" + safe + "' | wl-copy" +
            " && sleep 0.05" +
            " && wtype -M shift -P Insert -p Insert -m shift 2>/dev/null || true"]);
    }

    ListModel { id: displayModel }

    Process {
        id: fetchProc
        property string collected: ""
        stdout: SplitParser {
            onRead: (data) => fetchProc.collected += data + "\n"
        }
        onExited: {
            const lines = fetchProc.collected.split("\n");
            const out = [];
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                if (!line) continue;
                // cliphist format: "<id>\t<preview>". Image entries have a
                // preview like "[[ binary data N <type> bytes ]]".
                const tab = line.indexOf("\t");
                if (tab < 0) continue;
                const id = line.slice(0, tab);
                const preview = line.slice(tab + 1);
                const isImage = /^\[\[ binary data /.test(preview);
                out.push({
                    identifier: id,
                    preview: preview,
                    preview_type: isImage ? "image" : "text"
                });
            }
            root.items = out;
            root.rebuildDisplay();
        }
    }

    IpcHandler {
        target: "clipboard-picker"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closePicker(); return "ok" }
        function toggle(): string { root.togglePicker(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-clipboard-picker"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closePicker()

        // Lazy-load the picker's interior — the ListView + preview
        // pane only build on first open.
        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.opened || root._everLoaded
            sourceComponent: contentComponent
        }

        Component {
            id: contentComponent

        Item {
            anchors.fill: parent

            function scrollToSelected() {
                if (root.selectedIndex >= 0)
                    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
            }

            Component.onCompleted: Qt.callLater(() => keyCatcher.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => keyCatcher.forceActiveFocus());
                }
                function onSelectedIndexChanged() {
                    if (root.selectedIndex >= 0)
                        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
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
                        else root.closePicker();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1));
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.select(-1); event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.select(1); event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.select(-6); event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        root.select(6); event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activateIndex(root.selectedIndex); event.accepted = true;
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

                // Search header.
                Rectangle {
                    width: parent.width
                    height: root.headerHeight
                    color: "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || I18n.t("clipboard.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
                        font.family: root.fontFamily
                        font.pixelSize: Theme.fontPxLarge
                        elide: Text.ElideRight
                    }
                }

                // List + preview pane.
                Item {
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing

                    Row {
                        anchors.fill: parent
                        spacing: root.contentSpacing

                        ListView {
                            id: resultList
                            width: parent.width / 2 - root.contentSpacing / 2
                            height: parent.height
                            model: displayModel
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                required property int index
                                required property string identifier
                                required property string previewText
                                required property string previewType

                                width: ListView.view.width
                                height: root.rowHeight
                                radius: root.cornerRadius
                                color: index === root.selectedIndex
                                       ? root.withAlpha(root.foreground, 0.08)
                                       : root.withAlpha(root.foreground,
                                                        mouseArea.containsMouse ? 0.045 : 0)

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8

                                    Text {
                                        width: parent.width
                                        height: parent.height
                                        text: parent.parent.previewType === "text"
                                              ? parent.parent.previewText
                                              : I18n.t("clipboard.image")
                                        color: index === root.selectedIndex
                                               ? root.accent : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Theme.menuFontPx
                                        font.italic: parent.parent.previewType === "image"
                                        opacity: parent.parent.previewType === "image" ? 0.6 : 1.0
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
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
                                        root.activateIndex(index);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width / 2 - root.contentSpacing / 2
                            height: parent.height
                            radius: root.cornerRadius
                            color: root.withAlpha(root.background, 0.5)
                            border.color: root.withAlpha(root.border, 0.1)
                            border.width: 1
                            clip: true

                            property var activeRow:
                                displayModel.count > 0 &&
                                root.selectedIndex >= 0 &&
                                root.selectedIndex < displayModel.count
                                    ? displayModel.get(root.selectedIndex)
                                    : null

                            Text {
                                visible: parent.activeRow && parent.activeRow.previewType === "text"
                                anchors.fill: parent
                                anchors.margins: 16
                                text: parent.activeRow ? parent.activeRow.previewText : ""
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuFontPx
                                wrapMode: Text.WrapAnywhere
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignTop
                            }

                            Text {
                                visible: parent.activeRow && parent.activeRow.previewType === "image"
                                anchors.centerIn: parent
                                text: I18n.t("clipboard.image")
                                color: root.foreground
                                opacity: 0.5
                                font.family: root.fontFamily
                                font.italic: true
                                font.pixelSize: Theme.menuFontPx
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: displayModel.count === 0

                        Text {
                            text: "󰅌"
                            color: root.accent
                            opacity: 0.8
                            font.family: root.fontFamily
                            font.pixelSize: 28
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                        Text {
                            text: root.items.length === 0
                                  ? I18n.t("clipboard.empty")
                                  : I18n.t("emoji.no_matches", root.filterText)
                            color: root.foreground
                            opacity: 0.7
                            font.family: root.fontFamily
                            font.pixelSize: Theme.menuFontPx
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                    }
                }
            }
        }
        }
        }
    }
