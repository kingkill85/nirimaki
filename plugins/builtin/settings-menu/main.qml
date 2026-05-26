import Quickshell
import Quickshell.Io
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
// Trigger: `quickshell ipc call shell toggle settings-menu`.
// Lazy-summoned by the v2 plugin host (kind: menu).
Item {
    id: root

    property bool opened: false

    // Loaded == summoned: snap to open.
    Component.onCompleted: opened = true

    onOpenedChanged: {
        if (opened) {
            PopupBus.show(root);
        } else {
            PopupBus.hide(root);
            Plugins.hide("settings-menu");
        }
    }

    readonly property int cardWidth: 480
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

    function closeMenu() { opened = false }

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
            // External IPC target (not the shell). Fire synchronously
            // while the menu QML is still alive — the menu is itself
            // lazy-summoned now, so any Qt.callLater deferral would
            // run AFTER closeMenu() has triggered Plugins.hide() and
            // the Loader has torn this QML down, cancelling the
            // deferred callback.
            const target = a.target, fn = a.fn || "toggle";
            const args = (a.args || []).map(root._expandHome);
            Quickshell.execDetached(
                ["quickshell", "ipc", "call", "--", target, fn].concat(args));
        } else if (a.type === "summon") {
            // Call Plugins.summon directly instead of bouncing through
            // `shell summon` IPC. Same reason as above — and one
            // singleton call is cheaper than a subprocess.
            Plugins.summon(a.id || "", a.payload ? JSON.stringify(a.payload) : "");
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

        // The outer summon-Loader in shell.qml gates QML
        // instantiation on first open; this inner Loader stays around
        // only because the sourceComponent → MenuView path is wired
        // through Loader.onLoaded.
        Loader {
            id: menuLoader
            anchors.fill: parent
            active: true

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
                    // Dispatch FIRST: closeMenu() tears this QML down
                    // synchronously (Plugins.hide unloads the outer
                    // summon-Loader), so any code after closeMenu runs
                    // in an invalidated context — `_dispatch` itself
                    // becomes undefined. Run the action while we're
                    // still alive, then close.
                    root._dispatch(action);
                    root.closeMenu();
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
