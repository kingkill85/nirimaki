import Quickshell
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs

// Theme picker — overlay that lists every directory under
// ~/.config/theme/themes/ and runs `nirimaki-theme-set <name>` on Enter.
// Same UX shape as PowerMenu / EmojiPicker / ClipboardPicker: scrim
// over the workspace, centred card, fuzzy filter, accent-coloured
// selected row.
//
// Trigger: `quickshell ipc call shell toggle theme-picker`.
// Lazy-summoned by the v2 plugin host.
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property var themeNames: []         // alphabetically sorted

    // Loaded == summoned: snap to open, seed selection to active theme.
    Component.onCompleted: {
        loadThemeList();
        const cur = Theme.themeName;
        const idx = themeNames.indexOf(cur);
        selectedIndex = idx >= 0 ? idx : 0;
        rebuild();
        for (let i = 0; i < displayModel.count; i++) {
            if (displayModel.get(i).name === cur) { selectedIndex = i; break; }
        }
        opened = true;
    }

    onOpenedChanged: {
        if (opened) {
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
            Plugins.hide("theme-picker");
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
    readonly property int rowSpacing:     Theme.menuRowSpacing
    readonly property int rowHeight:      Theme.menuRowHeight
    readonly property int cardWidth: 360
    readonly property int cardHeight: 540

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function open() {
        opened = true;
        filterText = "";
        // Seed selection to the currently-active theme so the picker
        // opens "on" it; user can arrow-key away or filter to switch.
        loadThemeList();
        const cur = Theme.themeName;
        const idx = themeNames.indexOf(cur);
        selectedIndex = idx >= 0 ? idx : 0;
        rebuild();
        // Re-seek the active theme in the FILTERED list (rebuild()
        // doesn't know about our seed); falls back to 0.
        for (let i = 0; i < displayModel.count; i++) {
            if (displayModel.get(i).name === cur) { selectedIndex = i; break; }
        }
        // Focus is grabbed inside the content Component via Connections
        // on root.opened.
    }

    function closeMenu() { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function loadThemeList() {
        // FolderListModel can't be queried imperatively very easily;
        // it auto-populates `themesDir`. We mirror its contents into
        // our own array on every open and on dir change.
        const names = [];
        for (let i = 0; i < themesDir.count; i++) {
            const n = themesDir.get(i, "fileName");
            if (n && n.charAt(0) !== ".") names.push(n);
        }
        names.sort((a, b) => a.localeCompare(b));
        themeNames = names;
    }

    function rebuild() {
        displayModel.clear();
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < themeNames.length; i++) {
            const n = themeNames[i];
            if (!q || n.toLowerCase().indexOf(q) >= 0) {
                displayModel.append({ name: n, index: displayModel.count });
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

    // ListView position follows selectedIndex via Connections inside
    // the content Component below.
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
        const name = displayModel.get(idx).name;
        closeMenu();
        // nirimaki-theme-set lives in ~/.local/bin which niri's spawn path
        // doesn't include — use the absolute path.
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.local/bin/nirimaki-theme-set",
            name
        ]);
    }

    FolderListModel {
        id: themesDir
        folder: "file://" + Quickshell.env("HOME") + "/.config/theme/themes"
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        onCountChanged: if (root.opened) { root.loadThemeList(); root.rebuild(); }
    }

    ListModel { id: displayModel }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-theme-picker"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closeMenu()

        // The outer summon-Loader in shell.qml gates QML
        // instantiation on first open; this inner Loader is now an
        // always-on wrapper preserving the inner Component boundary
        // (which keeps inner ids isolated from root).
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

            function scrollToSelected() {
                if (root.selectedIndex >= 0)
                    rowList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
            }

            Component.onCompleted: Qt.callLater(() => keyCatcher.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => keyCatcher.forceActiveFocus());
                }
                function onSelectedIndexChanged() {
                    if (root.selectedIndex >= 0)
                        rowList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
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
                        if (root.filterText.length > 0)
                            root.setFilter(root.filterText.slice(0, -1));
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

                // Search / placeholder header.
                Item {
                    width: parent.width
                    height: root.headerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || I18n.t("theme.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
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
                        required property string name
                        readonly property bool selected: index === root.selectedIndex
                        readonly property bool isCurrent: name === Theme.themeName

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

                            // Bullet glyph — filled when this is the active
                            // theme, empty otherwise. nf-md circles.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.isCurrent ? "" : ""
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuIconPx
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.name
                                color: row.selected ? root.accent : root.foreground
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
