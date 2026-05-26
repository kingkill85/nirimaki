import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Emoji picker — ported from Omarchy's shell/plugins/emoji-picker/
// EmojiPicker.qml (omarchy-shell branch). Their emojis.json is shipped
// alongside this file at ~/.config/quickshell/emojis.json (1870 entries
// in `{ e: "<emoji>", k: "<space-separated keywords>" }` shape).
//
// Activation pastes via wtype (same trick as the ClipboardPicker).
// Trigger: `quickshell ipc call shell toggle emoji-picker` (bound to
// Mod+E in niri config). Lazy-summoned by the v2 plugin host.
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

    // Loaded == summoned: snap to open.
    Component.onCompleted: { opened = true; rebuildDisplay(); }

    onOpenedChanged: {
        if (opened) {
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
            Plugins.hide("emoji-picker");
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
        // Focus is grabbed inside the content Component via Connections
        // on root.opened — see Loader below.
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

    // Plain JS array as the GridView model — was a ListModel with
    // clear() + append-per-item on every keystroke, which churns hard
    // across 1870 entries. With a JS array we recompute once and
    // assign in one shot; the delegate reads modelData.emoji.
    property var displayModel: []

    function rebuildDisplay() {
        const q = filterText.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < emojis.length; i++) {
            const it = emojis[i];
            if (!q || it.k.indexOf(q) >= 0) {
                out.push({ emoji: it.e, index: out.length });
                if (out.length >= 1000) break;
            }
        }
        displayModel = out;
        if (displayModel.length === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.length) selectedIndex = displayModel.length - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
        Qt.callLater(() => {
            if (contentLoader.item && displayModel.length > 0)
                contentLoader.item.scrollToSelected();
        });
    }

    // Positioning of the GridView is reactive via Connections inside
    // the content Component (sourceComponent: contentComponent below) —
    // see how it watches root.selectedIndex. So these functions just
    // update the index; auto-scroll follows.
    function select(delta) {
        if (displayModel.length === 0) return;
        selectedIndex = (selectedIndex + delta + displayModel.length) % displayModel.length;
    }
    function selectRow(delta) {
        if (displayModel.length === 0) return;
        let next = selectedIndex + delta * columns;
        if (next < 0) next = 0;
        if (next >= displayModel.length) next = displayModel.length - 1;
        selectedIndex = next;
    }
    function selectPage(delta) {
        if (displayModel.length === 0) return;
        // resultGrid lives inside the lazy-loaded Component; use the
        // exposed height ref to compute the page step, falling back to
        // a sensible default when the dialog hasn't loaded yet (this
        // function is keyboard-only so that case is unreachable).
        const gridH = contentLoader.item ? contentLoader.item.gridHeight : cardHeight - headerHeight;
        const visibleRows = Math.max(1, Math.floor(gridH / cellHeight));
        let next = selectedIndex + delta * columns * visibleRows;
        if (next < 0) next = 0;
        if (next >= displayModel.length) next = displayModel.length - 1;
        selectedIndex = next;
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        rebuildDisplay();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= displayModel.length) return;
        applySelected(displayModel[idx].emoji);
    }

    function applySelected(emoji) {
        if (!emoji) return;
        closePicker();
        const esc = String(emoji).replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-lc",
            "wl-copy '" + esc + "'; sleep 0.05; wtype '" + esc + "' 2>/dev/null || true"]);
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

        // The outer summon-Loader in shell.qml gates QML
        // instantiation on first open; this inner Loader is now an
        // always-on wrapper kept only to preserve the inner Component
        // boundary (which keeps inner ids isolated from root).
        Loader {
            id: contentLoader
            anchors.fill: parent
            active: true
            sourceComponent: contentComponent
        }

        Component {
            id: contentComponent

        Item {
            anchors.fill: parent

            // Exposed so outer rebuildDisplay() / selectPage() can drive
            // the GridView without reaching into its internal ids.
            property alias gridHeight: resultGrid.height
            function scrollToSelected() {
                if (root.selectedIndex >= 0)
                    resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
            }

            // Grab focus on open. Fires on first load (Component.onCompleted)
            // and on every subsequent open (Connections on root.opened).
            Component.onCompleted: Qt.callLater(() => keyCatcher.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => keyCatcher.forceActiveFocus());
                }
                function onSelectedIndexChanged() {
                    if (root.selectedIndex >= 0)
                        resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
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
                        model: root.displayModel
                        clip: true
                        cellWidth: root.cellWidth
                        cellHeight: root.cellHeight
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property int index
                            required property var modelData

                            width: root.cellWidth
                            height: root.cellHeight
                            radius: root.cornerRadius
                            color: index === root.selectedIndex
                                   ? root.withAlpha(root.foreground, 0.08)
                                   : root.withAlpha(root.foreground,
                                                    mouseArea.containsMouse ? 0.045 : 0)

                            Text {
                                text: parent.modelData.emoji
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
                        visible: root.displayModel.length === 0

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
        }
    }
