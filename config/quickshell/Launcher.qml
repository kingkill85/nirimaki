import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Application launcher styled to look + behave like Omarchy's walker.
// One instance per shell (NOT per screen).
// Trigger:   Mod+D → `quickshell ipc call launcher toggle`
//
// Surfaces are handled by DialogShell: scrim (no blur) + dialog
// (blurred behind translucent card), matching Omarchy's look.
Item {
    id: root

    property bool opened: false

    onOpenedChanged: {
        if (opened) {
            search.text = "";
            list.currentIndex = 0;
            Qt.callLater(() => search.forceActiveFocus());
        }
    }

    // ---- App data ----
    readonly property var entries:
        DesktopEntries.applications ? DesktopEntries.applications.values : []

    readonly property var filtered: {
        const term = search.text.toLowerCase().trim();
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
        const e = filtered[list.currentIndex];
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
        list.currentIndex = (list.currentIndex + delta + n) % n;
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "qs-launcher"
        cardWidth: 620
        cardHeight: 540
        cardColor: Theme.cardBg
        cardBorderColor: Theme.cardBorderColor
        cardRadius: Theme.radius

        onCloseRequested: root.opened = false

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

                    onTextChanged: list.currentIndex = 0
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
                currentIndex: 0
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
                        onEntered: list.currentIndex = index
                        onClicked: {
                            list.currentIndex = index;
                            root.launchSelected();
                        }
                    }
                }
            }
        }
    }

    // ---- IPC ----
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.opened = !root.opened }
        function show():   void { root.opened = true }
        function hide():   void { root.opened = false }
    }
}
