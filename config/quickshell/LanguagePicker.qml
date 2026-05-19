import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel

// Language picker — lists every <code>.json under
// ~/.config/quickshell/i18n/ and writes the chosen code to
// ~/.config/quickshell/locale. The I18n singleton reads that file
// first (before LC_MESSAGES / LANG) so the picker doubles as a
// runtime locale switcher.
//
// Trigger: `quickshell ipc call -- language-picker toggle`
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property var entries: []   // [{ code, name }]

    readonly property color accent:     Theme.accent
    readonly property color background: Theme.cardBg
    readonly property color foreground: Theme.fg
    readonly property color border:     Theme.cardBorderColor
    readonly property int   cornerRadius: Theme.radius
    readonly property string fontFamily: Theme.monoFamily

    readonly property int contentMargin:  Theme.menuMargin
    readonly property int headerHeight:   Theme.menuHeaderHeight
    readonly property int contentSpacing: Theme.menuSpacing
    readonly property int rowSpacing:     Theme.menuRowSpacing
    readonly property int rowHeight:      Theme.menuRowHeight
    readonly property int cardWidth: 360
    readonly property int cardHeight: 420

    // Code → human name. Add a new language by:
    //   1. Drop ~/.config/quickshell/i18n/<code>.json
    //   2. Add the name here (optional — falls back to the code)
    readonly property var languageNames: ({
        "en": "English",
        "de": "Deutsch",
        "fr": "Français",
        "es": "Español",
        "it": "Italiano",
        "pt": "Português",
        "nl": "Nederlands"
    })

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function open() {
        opened = true;
        filterText = "";
        loadEntries();
        rebuild();
        // Seed selection to the active locale.
        selectedIndex = 0;
        for (let i = 0; i < displayModel.count; i++) {
            if (displayModel.get(i).code === I18n.locale) { selectedIndex = i; break; }
        }
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }
    function closeMenu()  { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function loadEntries() {
        const list = [];
        // Synthetic first entry — wipes the locale override and falls
        // back to the system $LANG (the "default" behaviour the I18n
        // singleton uses when no override file is present).
        list.push({ code: "", name: I18n.t("language.system_default") });
        for (let i = 0; i < i18nDir.count; i++) {
            const n = i18nDir.get(i, "fileName");
            if (!n || !n.toLowerCase().endsWith(".json")) continue;
            const code = n.slice(0, -5).toLowerCase();
            list.push({
                code: code,
                name: languageNames[code] || code
            });
        }
        // Keep the system-default entry pinned at index 0; sort the
        // rest alphabetically.
        const head = list.slice(0, 1);
        const tail = list.slice(1).sort((a, b) => a.name.localeCompare(b.name));
        entries = head.concat(tail);
    }

    function rebuild() {
        displayModel.clear();
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (q && e.code.indexOf(q) < 0 && e.name.toLowerCase().indexOf(q) < 0) continue;
            displayModel.append({ code: e.code, name: e.name, index: displayModel.count });
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
        const code = displayModel.get(idx).code;
        const localeFile = Quickshell.env("HOME") + "/.config/quickshell/locale";
        closeMenu();
        if (code === "") {
            // System-default entry: delete the override file so I18n
            // falls back to $LANG / $LC_MESSAGES.
            Quickshell.execDetached(["rm", "-f", localeFile]);
        } else {
            Quickshell.execDetached(["sh", "-lc",
                "printf '%s\\n' " + JSON.stringify(code) +
                " > " + JSON.stringify(localeFile)
            ]);
        }
    }

    FolderListModel {
        id: i18nDir
        folder: "file://" + Quickshell.env("HOME") + "/.config/quickshell/i18n"
        showFiles: true
        showDirs: false
        showOnlyReadable: true
        nameFilters: ["*.json"]
        sortField: FolderListModel.Name
        onCountChanged: if (root.opened) { root.loadEntries(); root.rebuild(); }
    }

    ListModel { id: displayModel }

    IpcHandler {
        target: "language-picker"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closeMenu(); return "ok" }
        function toggle(): string { root.toggleMenu(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "qs-language-picker"
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

                Item {
                    width: parent.width
                    height: root.headerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText || I18n.t("language.placeholder")
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
                        required property string code
                        required property string name
                        readonly property bool selected: index === root.selectedIndex
                        // For the synthetic "System default" entry (code === "")
                        // current = "no override active". For real codes, current
                        // = matches the resolved locale AND an override is set.
                        readonly property bool isCurrent: code === ""
                                                          ? !I18n.hasOverride
                                                          : (I18n.hasOverride && code === I18n.locale)

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
                                text: row.isCurrent ? "" : ""
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuIconPx
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.name + "  (" + row.code + ")"
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.menuFontPx
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
