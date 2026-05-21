import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Emoji picker — ported from Omarchy's shell/plugins/emoji-picker/
// EmojiPicker.qml (omarchy-shell branch). Their emojis.json is shipped
// alongside this file at ~/.config/quickshell/emojis.json (1870 entries
// in `{ e: "<emoji>", k: "<space-separated keywords>" }` shape).
//
// Activation pastes via wtype (same trick as the ClipboardPicker).
// Trigger: `quickshell ipc call -- emoji-picker toggle` (bound to
// Mod+E in niri config).
//
// Adaptations from upstream:
//   - qs.Commons (Color.menu.* / Style.cornerRadius / OMARCHY_MENU_FONT)
//     → Theme.qml singleton.
//   - Removed plugin-system properties (omarchyPath, shell, manifest,
//     pluginRegistry, dismiss() callback).
//   - FileView path hardcoded to ~/.config/quickshell/emojis.json.
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property var emojis: []

    readonly property color accent:     Theme.accent
    readonly property color background: Theme.cardBg
    readonly property color foreground: Theme.fg
    readonly property color border:     Theme.cardBorderColor
    readonly property int cornerRadius: Theme.radius
    readonly property string fontFamily: Theme.monoFamily
    readonly property int contentMargin:  Theme.menuMargin
    readonly property int headerHeight:   Theme.menuHeaderHeight
    readonly property int contentSpacing: Theme.menuSpacing
    readonly property int cardWidth: 400
    readonly property int cardHeight: 500
    readonly property int cellWidth: 44
    readonly property int cellHeight: 44
    readonly property int columns: Math.floor((cardWidth - contentMargin * 2) / cellWidth)

    function open() {
        opened = true;
        filterText = "";
        selectedIndex = 0;
        rebuildDisplay();
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }
    function closePicker() { opened = false; }
    function togglePicker() { opened ? closePicker() : open(); }

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function loadEmojis(raw) {
        try {
            const data = JSON.parse(raw);
            root.emojis = data || [];
        } catch (e) {
            console.warn("Failed to parse emojis.json:", e);
            root.emojis = [];
        }
        if (opened) rebuildDisplay();
    }

    function rebuildDisplay() {
        const q = filterText.trim().toLowerCase();
        displayModel.clear();
        let outCount = 0;
        for (let i = 0; i < emojis.length; i++) {
            const it = emojis[i];
            if (!q || it.k.indexOf(q) >= 0) {
                displayModel.append({ emoji: it.e, index: outCount });
                outCount++;
                if (outCount >= 1000) break;
            }
        }
        if (displayModel.count === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
        Qt.callLater(() => {
            if (displayModel.count > 0) resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
        });
    }

    function select(delta) {
        if (displayModel.count === 0) return;
        selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }
    function selectRow(delta) {
        if (displayModel.count === 0) return;
        let next = selectedIndex + delta * columns;
        if (next < 0) next = 0;
        if (next >= displayModel.count) next = displayModel.count - 1;
        selectedIndex = next;
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }
    function selectPage(delta) {
        if (displayModel.count === 0) return;
        const visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight));
        let next = selectedIndex + delta * columns * visibleRows;
        if (next < 0) next = 0;
        if (next >= displayModel.count) next = displayModel.count - 1;
        selectedIndex = next;
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        rebuildDisplay();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= displayModel.count) return;
        applySelected(displayModel.get(idx).emoji);
    }

    function applySelected(emoji) {
        if (!emoji) return;
        closePicker();
        const esc = String(emoji).replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-lc",
            "wl-copy '" + esc + "'; sleep 0.05; wtype '" + esc + "' 2>/dev/null || true"]);
    }

    ListModel { id: displayModel }

    IpcHandler {
        target: "emoji-picker"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closePicker(); return "ok" }
        function toggle(): string { root.togglePicker(); return "ok" }
        function ping(): string   { return "ok" }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/emojis.json"
        onLoaded: root.loadEmojis(text())
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-emoji-picker"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closePicker()

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
                    } else if (event.key === Qt.Key_Left)      { root.select(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_Right)       { root.select(1);  event.accepted = true; }
                    else if (event.key === Qt.Key_Up)          { root.selectRow(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_Down)        { root.selectRow(1);  event.accepted = true; }
                    else if (event.key === Qt.Key_PageUp)      { root.selectPage(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_PageDown)    { root.selectPage(1);  event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activateIndex(root.selectedIndex);
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

                Rectangle {
                    width: parent.width
                    height: root.headerHeight
                    color: "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || I18n.t("emoji.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
                        font.family: root.fontFamily
                        font.pixelSize: Theme.fontPxLarge
                        elide: Text.ElideRight
                    }
                }

                Item {
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing

                    GridView {
                        id: resultGrid
                        anchors.fill: parent
                        model: displayModel
                        clip: true
                        cellWidth: root.cellWidth
                        cellHeight: root.cellHeight
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property int index
                            required property string emoji

                            width: root.cellWidth
                            height: root.cellHeight
                            radius: root.cornerRadius
                            color: index === root.selectedIndex
                                   ? root.withAlpha(root.foreground, 0.08)
                                   : root.withAlpha(root.foreground,
                                                    mouseArea.containsMouse ? 0.045 : 0)

                            Text {
                                text: parent.emoji
                                font.family: root.fontFamily
                                font.pixelSize: 24
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
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

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: displayModel.count === 0

                        Text {
                            text: "󰞅"
                            color: root.accent
                            opacity: 0.8
                            font.family: root.fontFamily
                            font.pixelSize: 28
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                        Text {
                            text: I18n.t("emoji.no_matches", root.filterText)
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
