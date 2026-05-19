import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

// Keybind cheat sheet — parses ~/.config/niri/keybinds.kdl and shows
// every bind grouped under its `===== <Section> =====` header.
// Replaces niri's built-in `show-hotkey-overlay`.
//
// Two columns: chord left, label right. Filter input on top.
// Trigger: `quickshell ipc call -- keybind-sheet toggle`.
Item {
    id: root

    property bool opened: false
    property string filterText: ""
    property string raw: ""
    property var rows: []   // [{kind: "section"|"bind", section?, chord?, label?}, …]

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

    readonly property int cardWidth: 760
    readonly property int cardHeight: 720
    readonly property int chordColumnWidth: 230  // left column

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function open() {
        opened = true;
        filterText = "";
        reparse();
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }
    function closeMenu()  { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    function setFilter(next) {
        filterText = next;
        rebuildView();
    }

    // ---- Parser -------------------------------------------------
    // Walks `raw` line by line. Tracks current section from
    //   // ===== <Section> =====
    // Each bind line has the shape
    //   <CHORD> [attrs] { … }
    // where we want the chord plus, ideally, the hotkey-overlay-title
    // attribute. If no title is set, fall back to the first niri
    // action token inside the body braces.
    //
    // Handles multi-line bodies (the screenshot bind spans several
    // lines) by tracking brace depth so we skip continuation lines.
    function _parseRaw(text) {
        const out = [];
        const lines = String(text || "").split("\n");
        let section = "";
        let depth = 0;
        let inBinds = false;
        let pendingChord = null;

        const sectionRe = /^\s*\/\/\s*=====\s*(.+?)\s*=====/;
        const titleRe   = /hotkey-overlay-title="([^"]*)"/;
        // Chord = anything before the first whitespace, must start
        // with a recognised modifier/key — keeps us off comment + body
        // lines.
        const chordRe   = /^\s*((?:Mod|Super|Ctrl|Alt|Shift|XF86\w+|F\d+)(?:\+\S+)*)/;
        const actionRe  = /\{\s*([^;\s}]+)/;
        // Track the opening of the binds block so we don't accidentally
        // pick up nested {} elsewhere (theoretically there's none).
        const bindsOpen = /^\s*binds\s*\{/;

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            if (!inBinds) {
                if (bindsOpen.test(line)) inBinds = true;
                continue;
            }

            // Track brace depth so multi-line bind bodies don't get
            // re-parsed line by line.
            if (depth > 0) {
                for (const c of line) {
                    if (c === "{") depth++;
                    else if (c === "}") depth--;
                }
                if (depth <= 0) depth = 0;
                continue;
            }

            const sm = line.match(sectionRe);
            if (sm) {
                section = sm[1];
                out.push({ kind: "section", section: section });
                continue;
            }

            // Skip pure comments / blank lines.
            const trimmed = line.replace(/^\s+|\s+$/g, "");
            if (!trimmed || trimmed.startsWith("//")) continue;

            const cm = line.match(chordRe);
            if (!cm) continue;

            const chord = cm[1];
            let label = "";
            const tm = line.match(titleRe);
            if (tm) {
                label = tm[1];
            } else {
                const am = line.match(actionRe);
                if (am) label = am[1];
            }
            if (!label) label = "(unlabelled)";

            out.push({ kind: "bind", section: section, chord: chord, label: label });

            // If the line opens a body but doesn't close it on the same
            // line (multi-line spawn-sh), enter depth-tracking mode.
            let opens = 0, closes = 0;
            for (const c of line) {
                if (c === "{") opens++;
                else if (c === "}") closes++;
            }
            if (opens > closes) depth = opens - closes;
        }
        return out;
    }

    function reparse() {
        rows = _parseRaw(raw);
        rebuildView();
    }

    function rebuildView() {
        displayModel.clear();
        const q = filterText.trim().toLowerCase();
        let lastSection = "";
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            if (r.kind === "section") {
                lastSection = r.section;
                continue;
            }
            if (q) {
                const hit = r.chord.toLowerCase().indexOf(q) >= 0
                          || r.label.toLowerCase().indexOf(q) >= 0
                          || (r.section || "").toLowerCase().indexOf(q) >= 0;
                if (!hit) continue;
            }
            // Emit a section header on the FIRST visible row of each
            // section so filtered results stay grouped.
            if (r.section && r.section !== displayModel._lastSection) {
                displayModel.append({ kind: "section", section: r.section, chord: "", label: "" });
                displayModel._lastSection = r.section;
            }
            displayModel.append({ kind: "bind", section: r.section || "",
                                  chord: r.chord, label: r.label });
        }
    }

    ListModel {
        id: displayModel
        property string _lastSection: ""
        onCountChanged: if (count === 0) _lastSection = ""
    }

    FileView {
        id: kdlFile
        path: Quickshell.env("HOME") + "/.config/niri/keybinds.kdl"
        watchChanges: true
        printErrors: false
        onLoaded:       { root.raw = text(); if (root.opened) root.reparse(); }
        onFileChanged:  reload()
        onLoadFailed:   { root.raw = ""; if (root.opened) root.reparse(); }
    }

    IpcHandler {
        target: "keybind-sheet"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closeMenu(); return "ok" }
        function toggle(): string { root.toggleMenu(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "qs-keybind-sheet"
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

                // Filter header.
                Item {
                    width: parent.width
                    height: root.headerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText
                              || I18n.t("keybinds.placeholder")
                        color: root.foreground
                        opacity: root.filterText ? 1 : 0.58
                        font.family: root.fontFamily
                        font.pixelSize: Theme.menuFontPx
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: list
                    width: parent.width
                    height: parent.height - root.headerHeight - root.contentSpacing
                    model: displayModel
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: row
                        required property string kind
                        required property string section
                        required property string chord
                        required property string label

                        width: ListView.view.width
                        height: row.kind === "section" ? 30 : 26

                        // ---- Section header ----
                        Text {
                            visible: row.kind === "section"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.topMargin: 10
                            text: row.section
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Theme.fontPx
                            font.bold: true
                        }

                        // ---- Bind row ----
                        Row {
                            visible: row.kind === "bind"
                            anchors.fill: parent
                            spacing: 12

                            Text {
                                width: root.chordColumnWidth
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.chord
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.fontPx
                            }
                            Text {
                                width: parent.width - root.chordColumnWidth - 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.label
                                color: root.foregroundDim
                                font.family: root.fontFamily
                                font.pixelSize: Theme.fontPx
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
