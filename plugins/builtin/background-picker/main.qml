import Quickshell
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs

// Background picker — overlay grid of every image under
// ~/.config/theme/current/backgrounds/. Enter writes a symlink
// `current/wallpaper -> <chosen>` and respawns swaybg via
// nirimaki-wallpaper-apply.
//
// The symlink lives until nirimaki-theme-set runs (theme swap clears it
// so each new theme starts on its own first image). Picker
// selection therefore persists across reboots within the same
// theme, but a theme change resets the wallpaper. Acceptable
// trade-off — wallpapers are theme-curated.
//
// Trigger: `quickshell ipc call shell toggle background-picker`.
// Lazy-summoned by the v2 plugin host.
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property var bgs: []          // sorted list of absolute image paths

    // Loaded == summoned: snap to open after collecting the listing.
    Component.onCompleted: {
        loadBgList();
        rebuild();
        opened = true;
    }

    onOpenedChanged: {
        if (opened) {
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
            Plugins.hide("background-picker");
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

    // Card is wider than ThemePicker — thumbnails need horizontal room.
    // `cellWidth` is derived from GridView's actual width at runtime
    // (see grid.cellWidth below); columns is just the target count.
    readonly property int cardWidth: 1000
    readonly property int cardHeight: 620
    readonly property int columns: 4

    // Point at the actual `themes/<name>/backgrounds` dir, not at
    // `current/backgrounds`. The latter is a symlink that swaps under
    // FolderListModel without changing the URL — so a theme swap
    // wouldn't refresh the listing. Binding to themeName makes the
    // URL itself change on swap, which FolderListModel does pick up.
    readonly property string bgDir:
        Quickshell.env("HOME") + "/.config/theme/themes/" + Theme.themeName + "/backgrounds"
    // User per-theme dir (Omarchy convention). Additive — images here
    // appear in the picker alongside the theme-shipped set.
    readonly property string userBgDir:
        Quickshell.env("HOME") + "/.config/nirimaki/backgrounds/" + Theme.themeName
    readonly property string pickPath:
        Quickshell.env("HOME") + "/.config/theme/current/wallpaper"

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function basename(path) {
        const i = path.lastIndexOf("/");
        return i >= 0 ? path.substring(i + 1) : path;
    }
    function stem(path) {
        const b = basename(path);
        const dot = b.lastIndexOf(".");
        return dot > 0 ? b.substring(0, dot) : b;
    }

    function open() {
        opened = true;
        filterText = "";
        loadBgList();
        rebuild();
        // Selection always seeds to first entry. Pre-refactor this
        // tried to seed to the currently-active wallpaper via a
        // FileView reading the `pickPath` symlink, but FileView reads
        // the resolved file's CONTENTS (binary image bytes), not the
        // symlink target — so `.text.trim()` threw a TypeError and
        // the match never worked. Reading the symlink target needs
        // a Process { command: ["readlink", "-f", pickPath] } pipe,
        // out of scope here.
        selectedIndex = 0;
        // Focus is grabbed inside the content Component via Connections
        // on root.opened.
    }

    function closeMenu() { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function loadBgList() {
        // Merge two FolderListModels: user per-theme dir (additive)
        // + theme-shipped dir. User images sort first by basename so
        // a user-prefixed `0-foo.jpg` lands ahead of any theme image.
        // Dedupe by basename in case both dirs happen to share a name.
        const seen = {};
        function collect(model, baseUrl) {
            const out = [];
            for (let i = 0; i < model.count; i++) {
                const n = model.get(i, "fileName");
                if (!n || n.charAt(0) === ".") continue;
                const lower = n.toLowerCase();
                if (!(lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
                      lower.endsWith(".png") || lower.endsWith(".webp"))) continue;
                if (seen[n]) continue;
                seen[n] = true;
                out.push(baseUrl + "/" + n);
            }
            return out;
        }
        const userImgs  = collect(userBgFolder, root.userBgDir);
        const themeImgs = collect(bgFolder,     root.bgDir);
        userImgs.sort((a, b)  => a.localeCompare(b));
        themeImgs.sort((a, b) => a.localeCompare(b));
        bgs = userImgs.concat(themeImgs);
    }

    function rebuild() {
        displayModel.clear();
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < bgs.length; i++) {
            const p = bgs[i];
            if (!q || basename(p).toLowerCase().indexOf(q) >= 0) {
                displayModel.append({
                    path: p, name: stem(p), index: displayModel.count
                });
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

    // GridView position follows selectedIndex via Connections inside
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
        const path = displayModel.get(idx).path;
        closeMenu();
        // 1. (Re-)create the symlink. `ln -sfn` is atomic-enough for
        //    this purpose and overwrites any existing symlink.
        // 2. Re-spawn swaybg via the apply script (it reads the
        //    symlink and starts a fresh swaybg pointed at it).
        Quickshell.execDetached(["sh", "-lc",
            "ln -sfn " + JSON.stringify(path) + " " + JSON.stringify(root.pickPath) +
            " && " + Quickshell.env("HOME") + "/.local/bin/nirimaki-wallpaper-apply"
        ]);
    }

    FolderListModel {
        id: bgFolder
        folder: "file://" + root.bgDir
        showFiles: true
        showDirs: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        onCountChanged: if (root.opened) { root.loadBgList(); root.rebuild(); }
    }

    FolderListModel {
        id: userBgFolder
        folder: "file://" + root.userBgDir
        showFiles: true
        showDirs: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        onCountChanged: if (root.opened) { root.loadBgList(); root.rebuild(); }
    }

    ListModel { id: displayModel }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-background-picker"
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
                    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
            }

            Component.onCompleted: Qt.callLater(() => keyCatcher.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => keyCatcher.forceActiveFocus());
                }
                function onSelectedIndexChanged() {
                    if (root.selectedIndex >= 0)
                        grid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
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
                        root.select(-root.columns); event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.select(root.columns); event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        root.select(-1); event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
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
                        text: root.filterText || I18n.t("background.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
                        font.family: root.fontFamily
                        font.pixelSize: Theme.menuFontPx
                        elide: Text.ElideRight
                    }
                }

                GridView {
                    id: grid
                    // Pin the GridView to a known width — the card width
                    // minus the Column's anchor margins on both sides.
                    // Binding `width: parent.width` was returning a
                    // smaller value (Column doesn't stretch its
                    // children), which collapsed the column count.
                    width: root.cardWidth - 2 * root.contentMargin
                    height: parent.height - root.headerHeight - root.contentSpacing
                    // `cellWidth` is the FULL slot (image + horizontal
                    // padding). Math.floor guarantees exactly `columns`
                    // cells fit, never floor-1 because of rounding.
                    cellWidth: width > 0 ? Math.floor(width / root.columns) : 1
                    cellHeight: Math.floor(cellWidth * 9 / 16) + 28  // thumb + label
                    model: displayModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: cell
                        required property int index
                        required property string path
                        required property string name
                        readonly property bool selected: index === root.selectedIndex
                        readonly property int padding: 4

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            id: thumbFrame
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: cell.padding
                            anchors.rightMargin: cell.padding
                            anchors.topMargin: cell.padding
                            // 16:9 image area; remaining ~24 px for label below.
                            height: Math.floor(width * 9 / 16)
                            radius: root.cornerRadius
                            color: cell.selected
                                   ? root.withAlpha(root.foreground, 0.08)
                                   : "transparent"
                            border.color: cell.selected ? root.accent : "transparent"
                            border.width: 2
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "file://" + cell.path
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width:  thumbFrame.width  * 2
                                sourceSize.height: thumbFrame.height * 2
                            }
                        }

                        Text {
                            anchors.top: thumbFrame.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 4
                            text: cell.name
                            color: cell.selected ? root.accent : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Theme.fontPx
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
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
