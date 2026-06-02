import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Stream Deck layout editor — lazy-summoned panel.
//
//   quickshell ipc call shell summon streamdeck-editor
//
// A visual stand-in for Elgato's Stream Deck software: a 5×3 grid of
// keys on the left, a per-key action editor on the right, a page
// switcher up top and a brightness slider + Save in the footer.
//
// The whole thing is a view onto ~/.config/nirimaki/streamdeck.json —
// the same friendly JSON that nirimaki-streamdeck-generate compiles into
// deckmaster .deck files. Edits live in-memory until Save, which hands
// the full document to nirimaki-streamdeck-set (validate → write →
// reload deckmaster). The plugin only loads when deckmaster is installed
// (requires.binary in plugin.json), so opening it always means a deck is
// present.
DialogShell {
    id: shell
    open: true
    dialogNamespace: "nirimaki-streamdeck-editor"

    onCloseRequested: Plugins.hide("streamdeck-editor")

    // ---- Deck model (mirror of streamdeck.json) ----
    // Plain JS object; reassigned wholesale via touch() so QML bindings
    // that read it re-evaluate (QML doesn't observe deep mutation).
    property var    deck: ({ version: 1, brightness: 70, pages: { main: [] } })
    property string currentPage: "main"
    property int    selectedIndex: -1
    property bool   loaded: false
    property bool   pageRenaming: false

    // ---- Deck geometry (different Stream Deck models, different grids) ----
    // A connected device wins (its grid is authoritative); otherwise fall
    // back to the cols/rows last saved in streamdeck.json (so offline editing
    // remembers the model), then to the 15-key 5×3 layout.
    property int detectedCols: 0
    property int detectedRows: 0
    readonly property int gridCols: detectedCols > 0 ? detectedCols
                                  : ((deck && deck.cols > 0) ? deck.cols : 5)
    readonly property int gridRows: detectedRows > 0 ? detectedRows
                                  : ((deck && deck.rows > 0) ? deck.rows : 3)
    readonly property int keyCount: gridCols * gridRows

    // Key cell + layout metrics — the card sizes itself to the grid so a
    // Mini (3×2), a 5×3, and an XL (8×4) all lay out correctly.
    readonly property int cellSize: 84
    readonly property int cellGap: 10
    readonly property int gridW: gridCols * cellSize + (gridCols - 1) * cellGap
    readonly property int gridH: gridRows * cellSize + (gridRows - 1) * cellGap
    readonly property int editorW: 280
    readonly property int bodyH: Math.max(gridH, 360)
    cardWidth: 18 + gridW + 18 + editorW + 18
    cardHeight: 18 + 40 + 14 + Theme.controlHeight + 16 + bodyH + 14 + Theme.controlHeight + 18

    // Detect the connected model's grid on open.
    Process {
        id: detectProc
        running: true
        command: [Quickshell.env("HOME") + "/.local/bin/nirimaki-streamdeck-detect"]
        stdout: StdioCollector {
            id: detectOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const g = JSON.parse(String(detectOut.text || "").trim());
                    if (g && g.cols > 0 && g.rows > 0) {
                        shell.detectedCols = g.cols;
                        shell.detectedRows = g.rows;
                    }
                } catch (e) { /* leave defaults */ }
            }
        }
    }

    // Installed themes, for the theme key's picker (so it can't be a typo
    // or — as easily — the already-active theme).
    property var themeNames: []
    Process {
        id: themesProc
        running: true
        command: ["bash", "-lc", Quickshell.env("HOME") + "/.local/bin/nirimaki theme list"]
        stdout: StdioCollector {
            id: themesOut
            waitForEnd: true
            onStreamFinished: {
                const out = [];
                const lines = String(themesOut.text || "").split("\n");
                for (const ln of lines) {
                    const n = ln.replace(/^\s*\*?\s*/, "").trim();  // drop "* " active marker + indent
                    if (n) out.push(n);
                }
                shell.themeNames = out;
            }
        }
    }

    // The high-level action types the generator understands, plus a
    // synthetic "(empty)" that clears the key. "Launch app" leads because
    // it's the common case — pick any installed app from the same source
    // the launcher uses. The legacy "webapp" type is normalised into
    // "app" on load (see loadFromText) so it doesn't need its own row.
    readonly property var typeList: [
        { t: "",          name: I18n.t("streamdeck.type.empty") },
        { t: "app",       name: I18n.t("streamdeck.type.app") },
        { t: "workspace", name: I18n.t("streamdeck.type.workspace") },
        { t: "niri",      name: I18n.t("streamdeck.type.niri") },
        { t: "volume",    name: I18n.t("streamdeck.type.volume") },
        { t: "mic-mute",  name: I18n.t("streamdeck.type.mic_mute") },
        { t: "theme",     name: I18n.t("streamdeck.type.theme") },
        { t: "page",      name: I18n.t("streamdeck.type.page") },
        { t: "exec",      name: I18n.t("streamdeck.type.exec") },
        { t: "status",    name: I18n.t("streamdeck.type.status") }
    ]

    // Installed applications, same source the launcher reads — sorted by
    // name, NoDisplay entries hidden.
    readonly property var installedApps: {
        const apps = DesktopEntries.applications;
        const v = apps && apps.values ? apps.values : [];
        return v.filter(e => e && !e.noDisplay)
                .slice()
                .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    }
    function appIndexById(id) {
        if (!id) return -1;
        for (let i = 0; i < installedApps.length; i++)
            if (installedApps[i].id === id) return i;
        return -1;
    }
    // We store the desktop entry's raw icon — either a freedesktop icon
    // NAME ("firefox") or an absolute path (webapp icons) — and let the
    // generator resolve a name to a real PNG file (deckmaster can't open
    // an image:// URL or an SVG). cleanIcon only strips a leftover
    // Quickshell image:// prefix from older saves; it keeps names.
    function cleanIcon(v) {
        if (!v || typeof v !== "string") return undefined;
        const s = v.replace(/^image:\/\/icon\//, "");
        return s.length ? s : undefined;
    }
    function appIconPath(e) {
        return (e && e.icon) ? e.icon : undefined;
    }

    // ----- model helpers -----
    function touch() { deck = JSON.parse(JSON.stringify(deck)); }
    function pageNames() { return deck && deck.pages ? Object.keys(deck.pages) : []; }
    function pageKeys() { return (deck && deck.pages && deck.pages[currentPage]) || []; }
    function keyAt(i) {
        const ks = pageKeys();
        for (let k = 0; k < ks.length; k++) if (ks[k].index === i) return ks[k];
        return null;
    }
    function curType() { const k = keyAt(selectedIndex); return k ? (k.type || "") : ""; }
    function curField(f, fb) { const k = keyAt(selectedIndex); return k && k[f] !== undefined ? k[f] : fb; }

    // Replace (or remove, when obj === null) the key at index i on the
    // current page, then refresh bindings.
    function setKey(i, obj) {
        if (!deck.pages[currentPage]) deck.pages[currentPage] = [];
        const ks = deck.pages[currentPage].filter(k => k.index !== i);
        if (obj) { obj.index = i; ks.push(obj); }
        ks.sort((a, b) => a.index - b.index);
        deck.pages[currentPage] = ks;
        touch();
    }
    function patchKey(i, partial) {
        const k = keyAt(i);
        if (!k) return;
        setKey(i, Object.assign({}, k, partial));
    }
    // Switching type resets the key to type-appropriate defaults while
    // keeping the human label.
    function setType(i, t) {
        if (t === "") { setKey(i, null); return; }
        const prev = keyAt(i) || {};
        const base = { index: i, type: t, label: prev.label || "" };
        if (t === "volume")    base.action = "mute-toggle";
        if (t === "workspace") base.n = 1;
        if (t === "status")  { base.widget = "time"; base.format = "%H:%i"; }
        setKey(i, base);
    }

    // ----- pages -----
    function addPage() {
        let n = 2, name = "page2";
        while (deck.pages[name]) { n++; name = "page" + n; }
        deck.pages[name] = [];
        touch();
        currentPage = name;
        selectedIndex = -1;
    }
    function deletePage() {
        const names = pageNames();
        if (names.length <= 1) return;   // never delete the last page
        delete deck.pages[currentPage];
        touch();
        currentPage = pageNames()[0];
        selectedIndex = -1;
    }
    // Returns "" on success, or a reason the rename was rejected.
    function renamePage(oldName, newName) {
        newName = (newName || "").trim();
        if (!newName || newName === oldName) return "";          // no-op
        if (deck.pages[newName] !== undefined) return "name in use";
        // Rebuild the pages map preserving order, with the key renamed.
        const np = {};
        for (const k of Object.keys(deck.pages))
            np[k === oldName ? newName : k] = deck.pages[k];
        deck.pages = np;
        // Repoint every page-switch key that targeted the old name.
        for (const pg of Object.keys(deck.pages))
            for (const key of deck.pages[pg])
                if (key && key.type === "page" && key.page === oldName) key.page = newName;
        if (currentPage === oldName) currentPage = newName;
        touch();
        return "";
    }

    // ----- persistence -----
    function loadFromText(t) {
        try {
            const o = JSON.parse(t);
            if (!o || typeof o !== "object") return false;
            if (!o.pages || typeof o.pages !== "object" || !Object.keys(o.pages).length)
                o.pages = { main: [] };
            if (typeof o.brightness !== "number") o.brightness = 70;
            if (typeof o.version !== "number") o.version = 1;
            // Fold the legacy "webapp" type into the unified "app" type:
            // a nirimaki webapp is just a desktop entry with the id
            // nirimaki-webapp-<slug>, which the app picker handles.
            for (const pg of Object.keys(o.pages)) {
                if (!Array.isArray(o.pages[pg])) { o.pages[pg] = []; continue; }
                o.pages[pg] = o.pages[pg].map(k => {
                    if (k && k.type === "webapp")
                        k = { index: k.index, type: "app",
                              id: "nirimaki-webapp-" + (k.app || ""),
                              label: k.label || "", icon: k.icon };
                    // Normalise stored icons to a real file path (drops any
                    // leftover image:// URL from an earlier save).
                    if (k && k.icon !== undefined) k.icon = shell.cleanIcon(k.icon);
                    return k;
                });
            }
            shell.deck = o;
            // Keep the user on their page across our own save→reload cycle.
            if (!o.pages[shell.currentPage]) shell.currentPage = Object.keys(o.pages)[0];
            shell.loaded = true;
            return true;
        } catch (e) {
            console.warn("streamdeck-editor: bad JSON:", e.toString());
            return false;
        }
    }
    function save() {
        // Pull focus off any text/number field first so its commit-on-blur
        // fires and the edit lands in the model before we serialize.
        focusSink.forceActiveFocus();
        // Remember the current grid geometry so editing later with no device
        // attached still shows the right model.
        shell.deck.cols = shell.gridCols;
        shell.deck.rows = shell.gridRows;
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.local/bin/nirimaki-streamdeck-set",
            JSON.stringify(shell.deck)
        ]);
        savedHint.flash();
    }
    // Bring the daemon back without saving — recovery for a crashed deck
    // (the editor is reachable whenever deckmaster is installed, so this
    // works even when the deck is dark).
    function restart() {
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.local/bin/nirimaki-streamdeck-restart"
        ]);
        savedHint.flashText(I18n.t("streamdeck.restarting"));
    }

    // Real config first; fall back to the shipped sample so the editor
    // is populated out of the box before the user has saved anything.
    FileView {
        id: cfgFile
        path: Quickshell.env("HOME") + "/.config/nirimaki/streamdeck.json"
        watchChanges: true
        printErrors: false
        onLoaded: shell.loadFromText(text())
        onFileChanged: reload()
        onLoadFailed: sampleFile.reload()
    }
    FileView {
        id: sampleFile
        path: Quickshell.env("HOME") + "/.config/nirimaki/streamdeck.json.sample"
        printErrors: false
        onLoaded: shell.loadFromText(text())
    }

    // Escape closes. Also serves as a focus sink: forcing focus here on
    // save commits any field that only writes back on focus-loss.
    Item {
        id: focusSink
        width: 0; height: 0
        focus: true
        Keys.onEscapePressed: Plugins.hide("streamdeck-editor")
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18

        // ---- Header ----
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12
            height: 40

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍹"
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.fontPxLarge + 4
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: parent.width - 28 - closeBtn.width - parent.spacing * 2
                Text {
                    text: I18n.t("streamdeck.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                }
                Text {
                    text: I18n.t("streamdeck.subtitle")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
            Button {
                id: closeBtn
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.t("streamdeck.close")
                onTriggered: Plugins.hide("streamdeck-editor")
            }
        }

        // ---- Page switcher ----
        Row {
            id: pageRow
            anchors.top: header.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("streamdeck.page")
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
            }
            Dropdown {
                id: pagePicker
                visible: !shell.pageRenaming
                width: 200
                model: shell.pageNames()
                currentIndex: shell.pageNames().indexOf(shell.currentPage)
                placeholder: "—"
                onSelected: (i, item) => { shell.currentPage = item; shell.selectedIndex = -1; }
            }
            TextField {
                id: renameField
                visible: shell.pageRenaming
                width: 200
                anchors.verticalCenter: parent.verticalCenter
                placeholder: I18n.t("streamdeck.page_name")
                // Enter commits the rename.
                onAccepted: (t) => { shell.renamePage(shell.currentPage, t); shell.pageRenaming = false; }
            }
            Button {
                visible: !shell.pageRenaming
                label: I18n.t("streamdeck.rename")
                onTriggered: {
                    renameField.text = shell.currentPage;
                    shell.pageRenaming = true;
                    renameField.focusInput();
                }
            }
            Button {
                visible: shell.pageRenaming
                label: I18n.t("streamdeck.confirm")
                variant: Button.Primary
                onTriggered: { shell.renamePage(shell.currentPage, renameField.text); shell.pageRenaming = false; }
            }
            Button {
                visible: shell.pageRenaming
                label: I18n.t("streamdeck.cancel")
                onTriggered: shell.pageRenaming = false
            }
            Button {
                visible: !shell.pageRenaming
                label: I18n.t("streamdeck.add_page")
                onTriggered: shell.addPage()
            }
            Button {
                visible: !shell.pageRenaming
                label: I18n.t("streamdeck.delete_page")
                variant: Button.Urgent
                enabled: shell.pageNames().length > 1
                onTriggered: shell.deletePage()
            }
        }

        // ---- Body: key grid (left) + key editor (right) ----
        Row {
            id: body
            anchors.top: pageRow.bottom
            anchors.topMargin: 16
            anchors.bottom: footer.top
            anchors.bottomMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 18

            // ----- Key grid -----
            Grid {
                id: grid
                columns: shell.gridCols
                rows: shell.gridRows
                spacing: shell.cellGap
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: shell.keyCount
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        // re-read when the deck or page changes
                        readonly property var keyObj: (shell.deck, shell.currentPage, shell.keyAt(index))
                        readonly property bool isSel: shell.selectedIndex === index
                        width: shell.cellSize; height: shell.cellSize
                        radius: Theme.radius
                        color: keyObj
                               ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)
                               : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.02)
                        border.color: isSel ? Theme.accent
                                            : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.5)
                        border.width: isSel ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        // index marker (top-left)
                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.margins: 5
                            text: cell.index
                            color: Theme.fgDim
                            opacity: 0.6
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx - 4
                        }
                        // label / type preview (center)
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: cell.keyObj
                                  ? (cell.keyObj.label && cell.keyObj.label.length
                                     ? cell.keyObj.label
                                     : (cell.keyObj.type || ""))
                                  : "+"
                            color: cell.keyObj ? Theme.fg : Theme.fgDim
                            opacity: cell.keyObj ? 1.0 : 0.45
                            font.family: Theme.sansFamily
                            font.pixelSize: cell.keyObj ? Theme.fontPx : Theme.fontPxLarge
                            font.bold: !!(cell.keyObj && cell.keyObj.label)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.selectedIndex = cell.index
                        }
                    }
                }
            }

            // ----- Key editor -----
            Item {
                width: parent.width - grid.width - parent.spacing
                height: parent.height

                // Empty-state hint
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    visible: shell.selectedIndex < 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: I18n.t("streamdeck.empty_hint")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                }

                Flickable {
                    anchors.fill: parent
                    visible: shell.selectedIndex >= 0
                    contentHeight: editCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: editCol
                        width: parent.width
                        spacing: 10

                        Row {
                            width: parent.width
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - clearBtn.width
                                text: I18n.t("streamdeck.key").replace("{0}", shell.selectedIndex)
                                color: Theme.fg
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx
                                font.bold: true
                            }
                            Button {
                                id: clearBtn
                                label: I18n.t("streamdeck.clear")
                                variant: Button.Urgent
                                enabled: shell.keyAt(shell.selectedIndex) !== null
                                onTriggered: shell.setKey(shell.selectedIndex, null)
                            }
                        }

                        // Type
                        Column {
                            width: parent.width; spacing: 4
                            Text { text: I18n.t("streamdeck.action"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                id: typePicker
                                width: parent.width
                                model: shell.typeList
                                textRole: "name"
                                valueRole: "t"
                                currentIndex: {
                                    const t = shell.curType();
                                    for (let i = 0; i < shell.typeList.length; i++)
                                        if (shell.typeList[i].t === t) return i;
                                    return 0;
                                }
                                onSelected: (i, item) => shell.setType(shell.selectedIndex, item.t)
                            }
                        }

                        // Label (every real type)
                        EditRow {
                            label: I18n.t("streamdeck.label")
                            visible: shell.curType() !== ""
                            value: shell.curField("label", "")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex, { label: v })
                        }

                        // app → installed-application picker (the easy path:
                        // search any installed app, like the launcher)
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "app"
                            Text { text: I18n.t("streamdeck.application"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            SearchableDropdown {
                                width: parent.width
                                model: shell.installedApps
                                textRole: "name"
                                placeholder: I18n.t("streamdeck.app_search")
                                currentIndex: shell.appIndexById(shell.curField("id", ""))
                                onSelected: (i, item) => {
                                    if (!item) return;
                                    shell.patchKey(shell.selectedIndex, {
                                        id:    item.id,
                                        icon:  shell.appIconPath(item),
                                        label: (shell.curField("label", "") || item.name || ""),
                                        cmd:   undefined   // drop any legacy raw command
                                    });
                                }
                            }
                        }

                        // app → behavior when the app is already open
                        Toggle {
                            width: parent.width
                            visible: shell.curType() === "app"
                            label: I18n.t("streamdeck.launch_new")
                            description: I18n.t("streamdeck.launch_new_desc")
                            checked: shell.curField("reopen", "focus") === "launch"
                            onToggled: (c) => shell.patchKey(shell.selectedIndex,
                                                             { reopen: c ? "launch" : "focus" })
                        }

                        // exec → raw shell command (advanced escape hatch)
                        EditRow {
                            label: I18n.t("streamdeck.shell_command")
                            visible: shell.curType() === "exec"
                            value: shell.curField("cmd", "")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex, { cmd: v })
                        }

                        // niri → action
                        EditRow {
                            label: I18n.t("streamdeck.niri_action")
                            visible: shell.curType() === "niri"
                            value: shell.curField("action", "")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex, { action: v })
                        }

                        // workspace → n
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "workspace"
                            Text { text: I18n.t("streamdeck.workspace_number"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            NumberField {
                                width: parent.width
                                minimum: 1; maximum: 99; integer: true
                                value: shell.curField("n", 1)
                                onValueCommitted: (v) => shell.patchKey(shell.selectedIndex, { n: v })
                            }
                        }

                        // volume → action
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "volume"
                            Text { text: I18n.t("streamdeck.volume_action"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                width: parent.width
                                model: ["mute-toggle", "raise", "lower"]
                                currentIndex: Math.max(0, ["mute-toggle", "raise", "lower"]
                                                          .indexOf(shell.curField("action", "mute-toggle")))
                                onSelected: (i, item) => shell.patchKey(shell.selectedIndex, { action: item })
                            }
                        }

                        // theme → pick from installed themes
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "theme"
                            Text { text: I18n.t("streamdeck.theme"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                width: parent.width
                                model: shell.themeNames
                                currentIndex: shell.themeNames.indexOf(shell.curField("name", ""))
                                placeholder: I18n.t("streamdeck.theme_choose")
                                onSelected: (i, item) => shell.patchKey(shell.selectedIndex, { name: item })
                            }
                        }

                        // page → target page
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "page"
                            Text { text: I18n.t("streamdeck.switch_to_page"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                width: parent.width
                                model: shell.pageNames()
                                currentIndex: shell.pageNames().indexOf(shell.curField("page", ""))
                                placeholder: I18n.t("streamdeck.page_choose")
                                onSelected: (i, item) => shell.patchKey(shell.selectedIndex, { page: item })
                            }
                        }

                        // status → widget + sub-fields
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "status"
                            Text { text: I18n.t("streamdeck.widget"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                width: parent.width
                                model: ["time", "top", "command"]
                                currentIndex: Math.max(0, ["time", "top", "command"]
                                                          .indexOf(shell.curField("widget", "time")))
                                onSelected: (i, item) => shell.patchKey(shell.selectedIndex, { widget: item })
                            }
                        }
                        EditRow {
                            label: I18n.t("streamdeck.time_format")
                            visible: shell.curType() === "status" && shell.curField("widget", "time") === "time"
                            value: shell.curField("format", "%H:%i")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex, { format: v })
                        }
                        Column {
                            width: parent.width; spacing: 4
                            visible: shell.curType() === "status" && shell.curField("widget", "time") === "top"
                            Text { text: I18n.t("streamdeck.metric"); color: Theme.fgDim
                                   font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 1 }
                            Dropdown {
                                width: parent.width
                                model: ["cpu", "memory"]
                                currentIndex: Math.max(0, ["cpu", "memory"]
                                                          .indexOf(shell.curField("metric", "cpu")))
                                onSelected: (i, item) => shell.patchKey(shell.selectedIndex, { metric: item })
                            }
                        }
                        EditRow {
                            label: I18n.t("streamdeck.status_command")
                            visible: shell.curType() === "status" && shell.curField("widget", "time") === "command"
                            value: shell.curField("cmd", "")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex, { cmd: v })
                        }

                        // icon (optional, all real types)
                        EditRow {
                            label: I18n.t("streamdeck.icon_path")
                            visible: shell.curType() !== ""
                            value: shell.curField("icon", "")
                            onCommitted: (v) => shell.patchKey(shell.selectedIndex,
                                                               { icon: v.length ? v : undefined })
                        }
                    }
                }
            }
        }

        // ---- Footer: brightness (left) + actions (right) ----
        // Two anchored clusters rather than a Row-with-spacer, so the Save
        // button can never be pushed off the card edge regardless of label
        // widths or card size.
        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.controlHeight

            // Left: brightness
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t("streamdeck.brightness")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                }
                PanelSlider {
                    id: brightSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 180
                    minimum: 0; maximum: 100; integer: true; step: 5
                    value: (shell.deck && typeof shell.deck.brightness === "number")
                           ? shell.deck.brightness : 70
                    onReleased: (v) => { shell.deck.brightness = Math.round(v); shell.touch(); }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: Math.round(brightSlider.liveValue) + "%"
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                }
            }

            // Right: saved hint + actions
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    id: savedHint
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t("streamdeck.saved")
                    color: Theme.accent
                    opacity: 0
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    function flashText(msg) { text = msg; fade.restart(); }
                    function flash() { flashText(I18n.t("streamdeck.saved")); }
                    SequentialAnimation {
                        id: fade
                        NumberAnimation { target: savedHint; property: "opacity"; to: 1; duration: 120 }
                        PauseAnimation { duration: 1400 }
                        NumberAnimation { target: savedHint; property: "opacity"; to: 0; duration: 400 }
                    }
                }
                Button {
                    id: restartBtn
                    anchors.verticalCenter: parent.verticalCenter
                    label: I18n.t("streamdeck.restart")
                    variant: Button.Secondary
                    onTriggered: shell.restart()
                }
                Button {
                    id: saveBtn
                    anchors.verticalCenter: parent.verticalCenter
                    label: I18n.t("streamdeck.save")
                    variant: Button.Primary
                    onTriggered: shell.save()
                }
            }
        }
    }
}
