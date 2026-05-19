pragma Singleton
import QtQuick
import Quickshell.Io

// Shared niri IPC state.
// Subscribes once to `niri msg --json event-stream` and exposes the
// state every niri-aware widget needs.
QtObject {
    id: root

    // ---- Public state ----
    property var workspaces: []                              // list of workspace objects
    property var windows: ({})                               // id -> window object
    property int focusedWindowId: -1                         // -1 = no focus
    property int focusedWorkspaceId: -1
    property var keyboardLayouts: ({ names: [], currentIdx: 0 })

    // ---- Derived ----
    readonly property var focusedWindow:
        focusedWindowId >= 0 ? windows[focusedWindowId] : null
    readonly property string focusedWindowTitle:
        focusedWindow ? (focusedWindow.title || "") : ""
    readonly property string focusedWindowAppId:
        focusedWindow ? (focusedWindow.app_id || "") : ""
    readonly property string currentLayoutName:
        keyboardLayouts.names && keyboardLayouts.names.length
            ? keyboardLayouts.names[keyboardLayouts.currentIdx] || ""
            : ""

    // ---- Event handling ----
    function handleEvent(line) {
        if (!line) return;
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }

        if (ev.WorkspacesChanged) {
            const list = ev.WorkspacesChanged.workspaces;
            for (const w of list) if (w.is_focused) focusedWorkspaceId = w.id;
            workspaces = list;
        } else if (ev.WorkspaceActivated) {
            const id = ev.WorkspaceActivated.id;
            const focused = ev.WorkspaceActivated.focused;
            // find the activated workspace's output
            let activatedOutput = null;
            for (const w of workspaces) if (w.id === id) { activatedOutput = w.output; break; }
            const next = workspaces.map(w => {
                if (w.id === id) {
                    const nw = Object.assign({}, w, { is_active: true });
                    if (focused) nw.is_focused = true;
                    return nw;
                }
                if (w.output === activatedOutput) {
                    const nw = Object.assign({}, w, { is_active: false });
                    if (focused) nw.is_focused = false;
                    return nw;
                }
                return w;
            });
            if (focused) focusedWorkspaceId = id;
            workspaces = next;
        } else if (ev.WindowsChanged) {
            const map = {};
            let focusId = -1;
            for (const w of ev.WindowsChanged.windows) {
                map[w.id] = w;
                if (w.is_focused) focusId = w.id;
            }
            windows = map;
            focusedWindowId = focusId;
        } else if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window;
            const map = Object.assign({}, windows);
            map[w.id] = w;
            windows = map;
            if (w.is_focused) focusedWindowId = w.id;
        } else if (ev.WindowClosed) {
            const map = Object.assign({}, windows);
            delete map[ev.WindowClosed.id];
            windows = map;
            if (focusedWindowId === ev.WindowClosed.id) focusedWindowId = -1;
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id !== null
                              ? ev.WindowFocusChanged.id : -1;
        } else if (ev.KeyboardLayoutsChanged) {
            const kl = ev.KeyboardLayoutsChanged.keyboard_layouts;
            keyboardLayouts = { names: kl.names, currentIdx: kl.current_idx };
        } else if (ev.KeyboardLayoutSwitched) {
            keyboardLayouts = Object.assign({}, keyboardLayouts,
                                            { currentIdx: ev.KeyboardLayoutSwitched.idx });
        }
        // ignored events: OverviewOpenedOrClosed, ConfigLoaded, others
    }

    // ---- Event source ----
    property Process _eventStream: Process {
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: (data) => root.handleEvent(data)
        }
    }

    // ---- Convenience: actions ----
    // Run any `niri msg action <args...>` invocation.
    function runAction(/* ...args */) {
        const args = ["niri", "msg", "action"];
        for (let i = 0; i < arguments.length; i++) args.push(String(arguments[i]));
        actionProc.command = args;
        actionProc.startDetached();
    }

    function focusWorkspace(idx) { runAction("focus-workspace", idx); }

    property Process _actionProc: Process { id: actionProc }

    // Launch (or focus existing) a TUI in a floating kitty window.
    // app-id becomes "tui-<name>" so the niri ^tui- rule floats it.
    // Initial size is 120 cols × 32 rows — monitor-independent.
    function launchTui(/* name, ...cmd */) {
        const args = [];
        for (let i = 0; i < arguments.length; i++) args.push(String(arguments[i]));
        if (args.length === 0) return;
        const name = args[0];
        const cmd = args.slice(1);
        if (cmd.length === 0) cmd.push(name);   // default exec = name

        const wins = root.windows;
        for (const id in wins) {
            if ((wins[id].app_id || "") === ("tui-" + name)) {
                runAction("focus-window", "--id", String(wins[id].id));
                return;
            }
        }
        const kittyCmd = ["kitty",
            "--class=tui-" + name,
            "--override", "initial_window_width=120c",
            "--override", "initial_window_height=32c",
            "-e"
        ].concat(cmd);
        tuiProc.command = kittyCmd;
        tuiProc.startDetached();
    }

    property Process _tuiProc: Process { id: tuiProc }
}
