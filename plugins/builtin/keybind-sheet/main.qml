import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs

// Keybind cheat sheet — concatenates the Nirimaki default binds and
// the user's override file, then groups every bind under its
// `===== <Section> =====` header. Replaces niri's built-in
// `show-hotkey-overlay`.
//
// Reads:
//   ~/.local/share/nirimaki/default/niri/bindings.kdl   (defaults)
//   ~/.config/niri/bindings.kdl                          (user overrides)
//
// The user file usually has no section headers — its binds appear
// under a synthetic "User overrides" header injected at concat time.
//
// Two columns: chord left, label right. Filter input on top.
// Trigger: `quickshell ipc call -- keybind-sheet toggle`.
Item {
    id: root

    property bool opened: false
    property string rawDefault: ""
    property string rawUser: ""

    // Drives the lazy-loaded ListView's currentIndex from outside the
    // content Component. Filter text is similarly hoisted up here so
    // rebuildView() can read it without reaching into the Component.
    property int currentIndex: 0
    property string searchText: ""

    // Latched once the sheet has been opened — keeps the lazy-loaded
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
    readonly property string raw:
        rawDefault + "\n// ===== " + tr("section", "User overrides") + " =====\n" + rawUser
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

    // Translate-or-fall-back helper. Builds a slug key under
    // `keybind.<prefix>.<slug>`, returns the translated string if a
    // dictionary entry exists, otherwise the original. So
    // keybinds.kdl can stay in English and we only need to add
    // translations for the locales we ship.
    function _slug(s) {
        return String(s || "")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-|-$/g, "");
    }
    function tr(prefix, original) {
        const key = "keybind." + prefix + "." + _slug(original);
        const t = I18n.t(key);
        return t === key ? original : t;
    }

    function open() {
        opened = true;
        searchText = "";
        currentIndex = 0;
        reparse();
        // Search focus is grabbed inside the content Component via
        // Connections on root.opened — see Loader below.
    }
    function closeMenu()  { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    // Same pattern as Launcher: nudge currentIndex with bounds. The
    // ListView inside the content Component watches root.currentIndex
    // and scrolls to keep it visible.
    function move(delta) {
        const n = displayModel.count;
        if (n === 0) return;
        currentIndex = Math.max(0, Math.min(n - 1, currentIndex + delta));
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
        const q = searchText.trim().toLowerCase();
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
        id: defaultBinds
        path: Quickshell.env("HOME") + "/.local/share/nirimaki/default/niri/bindings.kdl"
        watchChanges: true
        printErrors: false
        onLoaded:       { root.rawDefault = text(); if (root.opened) root.reparse(); }
        onFileChanged:  reload()
        onLoadFailed:   { root.rawDefault = ""; if (root.opened) root.reparse(); }
    }

    FileView {
        id: userBinds
        path: Quickshell.env("HOME") + "/.config/niri/bindings.kdl"
        watchChanges: true
        printErrors: false
        onLoaded:       { root.rawUser = text(); if (root.opened) root.reparse(); }
        onFileChanged:  reload()
        onLoadFailed:   { root.rawUser = ""; if (root.opened) root.reparse(); }
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
        dialogNamespace: "nirimaki-keybind-sheet"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: root.background
        cardBorderColor: root.border
        cardRadius: root.cornerRadius

        onCloseRequested: root.closeMenu()

        // Lazy-load the sheet's interior — parses two kdl files and
        // builds a long ListView; only on first open.
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
            anchors.margins: root.contentMargin
            spacing: root.contentSpacing

            // Filter header — a real TextInput. Typing, backspace, text
            // cursor (Home/End within the text) are all native; we only
            // override the keys that should navigate the list.
            Item {
                width: parent.width
                height: root.headerHeight

                TextInput {
                    id: search
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.foreground
                    selectionColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    selectedTextColor: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Theme.menuFontPx
                    clip: true
                    focus: true

                    // Mirror typed text into root.searchText so the
                    // outer rebuildView() can read it. On root.open()
                    // searchText is reset to "" and reflected back here.
                    text: root.searchText
                    onTextChanged: {
                        if (root.searchText !== text) root.searchText = text;
                        root.currentIndex = 0;
                        root.rebuildView();
                    }

                    Keys.onEscapePressed: {
                        if (text) text = "";
                        else root.closeMenu();
                    }
                    Keys.onDownPressed: root.move(1)
                    Keys.onUpPressed:   root.move(-1)
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_PageDown) {
                            root.move(10);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.move(-10);
                            event.accepted = true;
                        }
                    }

                    Text {
                        visible: search.text === ""
                        anchors.fill: parent
                        text: I18n.t("keybinds.placeholder")
                        color: root.foreground
                        opacity: 0.58
                        font: search.font
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - root.headerHeight - root.contentSpacing
                model: displayModel
                currentIndex: root.currentIndex
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: row
                        required property string kind
                        required property string section
                        required property string chord
                        required property string label
                        readonly property bool selected: ListView.isCurrentItem && row.kind === "bind"

                        width: ListView.view.width
                        height: row.kind === "section" ? 30 : 26
                        radius: Theme.radius
                        color: row.selected
                               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                               : "transparent"

                        // ---- Section header ----
                        Text {
                            visible: row.kind === "section"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.topMargin: 10
                            text: root.tr("section", row.section)
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
                                color: row.selected ? root.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Theme.fontPx
                            }
                            Text {
                                width: parent.width - root.chordColumnWidth - 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.tr("title", row.label)
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
    }
}
