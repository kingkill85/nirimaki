import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs

// Unified settings menu — Omarchy-style drilldown wrapping the
// reusable MenuView primitive. SettingsMenu owns:
//   - the tree merge (defaults / generated / user) via three FileViews
//   - the installed-state file watch (for visibleWhen.feature gating)
//   - the action dispatcher (`_dispatch` — ipc / tui / shell / exec / …)
//   - the IpcHandler at target "settings-menu"
//   - the DialogShell wrapping
// All the drilldown / search / keyboard nav / ListView rendering lives
// inside MenuView so other plugins can use the same UI primitive.
//
// Trigger: `quickshell ipc call -- settings-menu toggle`
Item {
    id: root

    property bool opened: false
    property bool _everLoaded: false

    onOpenedChanged: {
        if (opened) {
            _everLoaded = true;
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
        }
    }

    readonly property int cardWidth: 380
    readonly property int cardHeight: 540

    // ---- Tree merge: defaults ← generated ← user --------------------
    // Loaded from config/quickshell/settings-menu.json + merged with the
    // auto-generated ~/.cache/nirimaki/menu-fonts.json and the user's
    // ~/.config/nirimaki/extensions/menu.json. Schema documented at the
    // top of the default JSON file.
    property var tree: ({})
    property var _defaultTree: ({})
    property var _generatedTree: ({})
    property var _userTree: ({})

    // Shallow id-level merge — user redefining an id fully replaces the
    // shipped node (no deep merge of children arrays; too clever, would
    // surprise on override).
    function _mergeTrees(base, extra) {
        const out = {};
        for (const k in base)  out[k] = base[k];
        for (const k in extra) {
            if (k === "_comment") continue;
            out[k] = extra[k];
        }
        return out;
    }

    function _loadTreeJson(raw, source) {
        if (!raw) return null;
        try {
            const parsed = JSON.parse(raw);
            delete parsed._comment;
            return parsed;
        } catch (e) {
            console.warn("SettingsMenu: failed to parse " + source + ":", e.toString());
            return null;
        }
    }

    function _rebuildTree() {
        root.tree = _mergeTrees(
            _mergeTrees(_defaultTree, _generatedTree),
            _userTree);
    }

    property FileView _defaultTreeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/settings-menu.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = root._loadTreeJson(text(), "settings-menu.json");
            if (t) { root._defaultTree = t; root._rebuildTree(); }
        }
        onFileChanged: reload()
    }

    // Auto-generated menu fragments (built by nirimaki-*-menu-refresh
    // scripts). Currently used for Style→Font dynamic drilldown.
    property FileView _generatedTreeFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/nirimaki/menu-fonts.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = root._loadTreeJson(text(), "cache/menu-fonts.json");
            root._generatedTree = t || ({});
            root._rebuildTree();
        }
        onFileChanged: reload()
        onLoadFailed: { root._generatedTree = ({}); root._rebuildTree(); }
    }

    property FileView _userTreeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/nirimaki/extensions/menu.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = root._loadTreeJson(text(), "extensions/menu.json");
            root._userTree = t || ({});
            root._rebuildTree();
        }
        onFileChanged: reload()
        onLoadFailed: { root._userTree = ({}); root._rebuildTree(); }
    }

    // ---- Install/Remove visibility gate -----------------------------
    // ~/.cache/nirimaki/state.json — populated by bin/nirimaki-feature-state
    // on session start + after each install/remove. Keys are feature
    // names matching `visibleWhen.feature` on JSON menu nodes; values
    // are booleans.
    property var installedState: ({})
    property FileView _stateFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/nirimaki/state.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.installedState = JSON.parse(text() || "{}"); }
            catch (e) { root.installedState = ({}); }
        }
        onFileChanged: reload()
        onLoadFailed: { root.installedState = ({}); }
    }

    // ---- Open / close / toggle --------------------------------------
    function open() {
        opened = true;
        // Reset path/filter every time we summon — even if opened was
        // already true (which would suppress the onOpenedChanged signal).
        if (menuLoader.item) {
            menuLoader.item.reset();
            Qt.callLater(menuLoader.item.focusMenu);
        }
    }
    function closeMenu()  { opened = false }
    function toggleMenu() { opened ? closeMenu() : open() }

    // ---- Action dispatcher ------------------------------------------
    function _expandHome(v) {
        if (typeof v === "string")
            return v.split("$HOME").join(Quickshell.env("HOME"));
        if (Array.isArray(v))
            return v.map(root._expandHome);
        return v;
    }

    // Dispatcher: map { type, ... } action records to runtime calls.
    // Types mirror the schema documented in settings-menu.json.
    function _dispatch(action) {
        if (!action || !action.type) return;
        const a = action;
        if (a.type === "ipc") {
            // Defer the IPC call so the menu finishes closing first —
            // otherwise some overlays open behind our backdrop.
            const target = a.target, fn = a.fn || "toggle";
            const args = (a.args || []).map(root._expandHome);
            Qt.callLater(() => Quickshell.execDetached(
                ["quickshell", "ipc", "call", "--", target, fn].concat(args)));
        } else if (a.type === "summon") {
            // Sugar over `{type: "ipc", target: "shell", fn: "summon",
            // args: [<id>, <payload>]}`. Used to open the new lazy-
            // overlay/panel plugins (audio mixer, future bluetooth /
            // network panels) from menu entries.
            const id = a.id || "";
            const payload = a.payload ? JSON.stringify(a.payload) : "";
            Qt.callLater(() => Quickshell.execDetached(
                ["quickshell", "ipc", "call", "--", "shell", "summon", id, payload]));
        } else if (a.type === "tui") {
            NiriService.launchTui.apply(null, [a.name].concat((a.exec || []).map(root._expandHome)));
        } else if (a.type === "shell") {
            Quickshell.execDetached(["sh", "-lc", root._expandHome(a.cmd)]);
        } else if (a.type === "exec") {
            Quickshell.execDetached((a.cmd || []).map(root._expandHome));
        } else if (a.type === "exec-in-foot") {
            const argv = ["foot", "--app-id=" + a.appId].concat(
                (a.cmd || []).map(root._expandHome));
            Quickshell.execDetached(argv);
        } else if (a.type === "quickshell-spawn") {
            Quickshell.execDetached(["quickshell", "-p", root._expandHome(a.path)]);
        } else {
            console.warn("SettingsMenu: unknown action type:", a.type);
        }
    }

    IpcHandler {
        target: "settings-menu"
        function summon(): string { root.open(); return "ok" }
        function hide(): string   { root.closeMenu(); return "ok" }
        function toggle(): string { root.toggleMenu(); return "ok" }
        function ping(): string   { return "ok" }
    }

    DialogShell {
        id: shell
        open: root.opened
        dialogNamespace: "nirimaki-settings-menu"
        cardWidth: root.cardWidth
        cardHeight: root.cardHeight
        cardColor: Theme.cardBg
        cardBorderColor: Theme.cardBorderColor
        cardRadius: Theme.radius

        onCloseRequested: root.closeMenu()

        // Lazy-load the menu's interior — MenuView only instantiates
        // on first open, then stays loaded for instant re-opens.
        Loader {
            id: menuLoader
            anchors.fill: parent
            active: root.opened || root._everLoaded

            sourceComponent: MenuView {
                // Loader doesn't auto-stretch its item; the MenuView root
                // is a bare Item with no implicit size, so without this
                // anchor it'd collapse to 0×0 and the menu would be invisible
                // even though it's loaded.
                anchors.fill: parent

                tree:           root.tree
                installedState: root.installedState
                placeholder:    I18n.t("settings.placeholder")

                onActionRequested: (action) => {
                    root.closeMenu();
                    root._dispatch(action);
                }
                onCloseRequested: root.closeMenu()
            }
        }

        // Reset path/filter/selection and grab focus on every open.
        Connections {
            target: root
            function onOpenedChanged() {
                if (root.opened && menuLoader.item) {
                    menuLoader.item.reset();
                    Qt.callLater(menuLoader.item.focusMenu);
                }
            }
        }
        // First-load focus when the Loader instantiates while opened.
        Connections {
            target: menuLoader
            function onLoaded() {
                if (root.opened && menuLoader.item)
                    Qt.callLater(menuLoader.item.focusMenu);
            }
        }
    }
}
