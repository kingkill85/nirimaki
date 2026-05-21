pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Theme singleton — palette comes from ~/.config/theme/current/{colors,
// shell}.toml. Both files are FileView-watched, so `qs-theme-set <name>`
// re-tints every widget within a frame or two without restarting
// quickshell.
//
// Sizing + font tokens stay hard-coded — those aren't per-theme.
QtObject {
    id: root

    // ===== Foundational palette (loaded from colors.toml) =====
    // Defaults preserved as fallback for the rare case the file is
    // missing or malformed — chosen so the shell still renders with the
    // same look the original hard-coded theme produced.
    property color fg:     "#cacccc"
    property color bg:     "#101315"
    property color accent: "#cacccc"
    property color urgent: "#a55555"
    property color cursor: "#cacccc"

    // ===== Derived (read-only — depend on the above via bindings) =====
    // Qt.lighter/darker scale by the given factor; values picked so the
    // results match the Phase-A hand-tuned #161a1d / #7a7c7c approximately.
    readonly property color bgAlt: Qt.lighter(bg, 1.4)
    readonly property color fgDim: Qt.darker(fg, 1.65)
    readonly property color hot:   Qt.rgba(accent.r, accent.g, accent.b, 0.12)

    // ===== Per-surface map (loaded from shell.toml; "<section>.<key>") =====
    property var shellValues: ({})

    function pick(key, fallback) {
        const v = shellValues[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    // ===== Sizing tokens =====
    readonly property int barHeight:   32
    readonly property int padX:        10
    readonly property int padY:        4
    readonly property int gap:         6
    readonly property int radius:      0
    readonly property int focusBorder: 3
    readonly property int fontPx:      13
    readonly property int iconPx:      15

    // ===== Fonts =====
    readonly property string monoFamily: "JetBrainsMono Nerd Font"
    readonly property string sansFamily: "JetBrainsMono Nerd Font"
    readonly property string iconFamily: "JetBrainsMono Nerd Font"

    // Tiny TOML-ish parser. We only need string values for
    //   key = "#rrggbb"   (foundational palette)
    //   [section]
    //   key = "value"     (shell.toml per-surface tokens)
    // so a real TOML library would be massive overkill. Tolerates inline
    // `# comments`, single or double quotes, and trailing whitespace.
    function loadColors(raw) {
        const lines = String(raw || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (!m) continue;
            const k = m[1];
            const v = m[2];
            if      (k === "foreground") fg     = v;
            else if (k === "background") bg     = v;
            else if (k === "accent")     accent = v;
            else if (k === "color1")     urgent = v;
            else if (k === "cursor")     cursor = v;
            // color0..color15 etc. aren't consumed by the QML side yet —
            // foot/btop pick those up via D3 templates.
        }
    }

    function loadShell(raw) {
        const parsed = {};
        let section = "";
        const lines = String(raw || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].replace(/^\s+|\s+$/g, "");
            if (!t || t.charAt(0) === "#") continue;
            const sm = t.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/);
            if (sm) { section = sm[1]; continue; }
            const km = t.match(/^([A-Za-z0-9_]+)\s*=\s*["']([^"']+)["']/);
            if (km && section) parsed[section + "." + km[1]] = km[2];
        }
        // Reassign whole object so QML bindings to `shellValues[...]`
        // re-evaluate. Mutating in place would not.
        shellValues = parsed;
    }

    // Manual reload trigger. `qs-theme-set` calls
    //   quickshell ipc call -- theme reload
    // after it rewrites the theme files, because inotify-based file
    // watches race against `cp` (truncate-then-write fires onFileChanged
    // while the file is still empty, then no second event when the
    // write finishes). Explicit IPC is reliable.
    function reload() {
        _colorsFile.reload();
        _shellFile.reload();
    }

    // IpcHandler must be attached via a property because QtObject has
    // no default child property.
    property IpcHandler _ipc: IpcHandler {
        target: "theme"
        function reload(): string { root.reload(); return "ok" }
        function ping(): string   { return "ok" }
    }

    // FileViews remain as a fallback for theme changes that happen
    // outside qs-theme-set (e.g. editing colors.toml by hand). The
    // watch may miss races but will eventually re-fire when the file
    // settles.
    property FileView _colorsFile: FileView {
        path: Quickshell.env("HOME") + "/.config/theme/current/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded:      root.loadColors(text())
        onFileChanged: reload()
        onLoadFailed:  root.loadColors("")
    }

    property FileView _shellFile: FileView {
        path: Quickshell.env("HOME") + "/.config/theme/current/shell.toml"
        watchChanges: true
        printErrors: false
        onLoaded:      root.loadShell(text())
        onFileChanged: reload()
        onLoadFailed:  root.loadShell("")
    }
}
