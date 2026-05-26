import QtQuick
import QtQuick.Controls
import Quickshell
import qs

// Application launcher styled to look + behave like Omarchy's walker.
// One instance per shell (NOT per screen). Lazy-summoned via
// `quickshell ipc call shell toggle launcher` — the outer Loader in
// shell.qml only instantiates this QML once summoned, so the bar pays
// nothing at startup.
//
// Surfaces are handled by DialogShell: scrim (no blur) + dialog
// (blurred behind translucent card), matching Omarchy's look.
Item {
    id: root

    // Plays back to PopupBus._close + tracked by onOpenedChanged so
    // writing `opened = false` from anywhere (Escape, click outside,
    // app launch) tears the overlay down via Plugins.hide.
    property bool opened: false

    // Drives the ListView's currentIndex + TextInput's text from
    // outside the content Component (which isolates inner ids).
    property int currentIndex: 0
    property string searchText: ""

    // Loaded == summoned: snap to open and grab the popup gate.
    Component.onCompleted: opened = true

    onOpenedChanged: {
        if (opened) {
            searchText = "";
            currentIndex = 0;
            PopupBus.show(root);
            // Focus is grabbed inside the content Component via
            // Connections on root.opened — see Loader below.
        } else {
            PopupBus.hide(root);
            Plugins.hide("launcher");
        }
    }

    // ---- App data ----
    readonly property var entries:
        DesktopEntries.applications ? DesktopEntries.applications.values : []

    readonly property var filtered: {
        const term = searchText.toLowerCase().trim();
        const arr = entries.filter(e => e && !e.noDisplay);
        if (!term) {
            return arr.slice().sort((a, b) =>
                (a.name || "").localeCompare(b.name || ""));
        }
        const match = (e) => {
            const n = (e.name || "").toLowerCase();
            const g = (e.genericName || "").toLowerCase();
            const c = (e.comment || "").toLowerCase();
            return n.indexOf(term) !== -1
                || g.indexOf(term) !== -1
                || c.indexOf(term) !== -1;
        };
        return arr.filter(match).sort((a, b) => {
            // Prioritize name-start matches, then name-contains, then alpha.
            const an = (a.name || "").toLowerCase();
            const bn = (b.name || "").toLowerCase();
            const aScore = an.startsWith(term) ? 0
                         : an.indexOf(term) !== -1 ? 1 : 2;
            const bScore = bn.startsWith(term) ? 0
                         : bn.indexOf(term) !== -1 ? 1 : 2;
            if (aScore !== bScore) return aScore - bScore;
            return an.localeCompare(bn);
        });
    }

    function launchSelected() {
        const e = filtered[currentIndex];
        if (!e) return;
        // .desktop entries with `Terminal=true` (nvim, htop, btop, etc.)
        // expect to be launched inside a terminal emulator. Quickshell's
        // built-in `execute()` runs the Exec line as-is, which for these
        // means "spawn nvim with no TTY" → exits instantly. Wrap in foot
        // when runInTerminal is set; tiled foot windows are the
        // appropriate Nirimaki host for TUI apps. (foot takes the
        // command as positional args after options — no `-e` like kitty.)
        if (e.runInTerminal && e.command && e.command.length > 0) {
            Quickshell.execDetached(["foot", ...e.command]);
        } else {
            e.execute();
        }
        root.opened = false;
    }

    function move(delta) {
        const n = filtered.length;
        if (n === 0) return;
        currentIndex = (currentIndex + delta + n) % n;
        // ListView position follows currentIndex via Connections inside
        // the content Component below.
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-launcher"
        cardWidth: 620
        cardHeight: 540
        cardColor: Theme.cardBg
        cardBorderColor: Theme.cardBorderColor
        cardRadius: Theme.radius

        onCloseRequested: root.opened = false

        // The outer summon-Loader in shell.qml already gates QML
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

            Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())
            Connections {
                target: root
                function onOpenedChanged() {
                    if (root.opened) Qt.callLater(() => search.forceActiveFocus());
                }
                function onCurrentIndexChanged() {
                    list.positionViewAtIndex(root.currentIndex, ListView.Contain);
                }
            }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.menuMargin
            spacing: Theme.menuSpacing

            // ---- Search field — input flush in card, no boxed container
            //                    (Omarchy walker: `.search-container`
            //                    is just padding, no background) ----
            Item {
                width: parent.width
                height: Theme.menuHeaderHeight

                TextInput {
                    id: search
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                    selectedTextColor: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.menuFontPx
                    clip: true
                    focus: true

                    // Mirror typed text into root.searchText so the
                    // outer `filtered` getter can read it. On root.open()
                    // searchText is reset to "" and reflected back here.
                    text: root.searchText
                    onTextChanged: {
                        if (root.searchText !== text) root.searchText = text;
                        root.currentIndex = 0;
                    }
                    onAccepted:    root.launchSelected()

                    Keys.onEscapePressed:  root.opened = false
                    Keys.onDownPressed:    root.move(1)
                    Keys.onUpPressed:      root.move(-1)
                    Keys.onTabPressed:     root.move(1)
                    Keys.onBacktabPressed: root.move(-1)

                    // Placeholder (Omarchy: `placeholder { opacity: 0.5 }`)
                    Text {
                        text: I18n.t("launcher.placeholder")
                        color: Theme.fgDim
                        opacity: 0.5
                        font: search.font
                        visible: search.text === ""
                    }
                }
            }

            // ---- Results list ----
            ListView {
                id: list
                width: parent.width
                height: parent.height - Theme.menuHeaderHeight - Theme.menuSpacing
                clip: true
                model: root.filtered
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                spacing: Theme.menuRowSpacing

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem

                    width: ListView.view.width
                    height: Theme.menuRowHeight
                    radius: Theme.radius
                    // Selected row: faint fg-tinted background, matches
                    // Omarchy walker `child:selected { background:
                    // alpha(@text, 0.07); }`. Selected text changes to
                    // accent (Omarchy: `color: @selected-text`).
                    color: row.selected
                           ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.07)
                           : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14

                        // Icon
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            source: modelData && modelData.icon
                                    ? Quickshell.iconPath(modelData.icon, true)
                                    : ""
                            visible: source !== ""
                        }

                        // Name only — Omarchy walker hides the subtitle via
                        // `.item-subtext { font-size: 0px; }`. Single line
                        // means the icon sits on the same baseline as the
                        // text, matching Omarchy's row look.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 32 - 14
                            text: (modelData && modelData.name) || ""
                            color: row.selected ? Theme.accent : Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.menuFontPx
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: root.currentIndex = index
                        onClicked: {
                            root.currentIndex = index;
                            root.launchSelected();
                        }
                    }
                }
            }
        }
        }
        }
    }

}
