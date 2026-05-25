pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// shell.json — the user's authoritative shell config. One file owns
// bar position, positional layout (left/center/right arrays of
// `{id, ...settings}` entries), and any non-bar plugin settings.
//
//   ~/.config/nirimaki/shell.json
//
// Schema (version 1):
//
//   {
//     "version": 1,
//     "bar": {
//       "position": "top",
//       "layout": {
//         "left":   [{"id": "workspaces"}, {"id": "active-window"}],
//         "center": [{"id": "calendar", "format": "dddd HH:mm"}, ...],
//         "right":  [{"id": "audio"}, {"id": "tray"}, ...]
//       }
//     },
//     "plugins": []          // reserved for non-bar plugin entries
//   }
//
// Inline settings on a layout entry are read by the plugin via
// `Plugins.settingFor(id, key, fallback)` — they're whatever the
// plugin understands. The shell never inspects them itself; they
// flow through from JSON to the plugin's `settings` property
// (injected by Bar.qml on Loader.onLoaded, same pattern as
// `barWindow` / `outputName`).
//
// When the file is missing or invalid, `valid` is false and
// `Plugins.qml` falls back to deriving the layout from manifests
// directly (the v1 behaviour).
QtObject {
    id: root

    readonly property string path:
        Quickshell.env("HOME") + "/.config/nirimaki/shell.json"

    // Parsed shell.json or empty object when missing/invalid.
    property var data: ({})

    // True iff shell.json was successfully parsed AND has a v1+ schema.
    property bool valid: false

    // ---- Public API ----

    // Effective bar position. "top" / "bottom" / "left" / "right".
    readonly property string barPosition:
        valid && data.bar && data.bar.position
            ? String(data.bar.position) : "top"

    // Positional layout per bar section. Each entry is an object with
    // at minimum `{id: string}` plus arbitrary plugin-defined settings.
    readonly property var barLeft:
        valid && data.bar && data.bar.layout && Array.isArray(data.bar.layout.left)
            ? data.bar.layout.left : []
    readonly property var barCenter:
        valid && data.bar && data.bar.layout && Array.isArray(data.bar.layout.center)
            ? data.bar.layout.center : []
    readonly property var barRight:
        valid && data.bar && data.bar.layout && Array.isArray(data.bar.layout.right)
            ? data.bar.layout.right : []

    // Look up a setting for a plugin id within the bar layout. Returns
    // `fallback` if the plugin isn't in any bar section or the key is
    // absent. For multi-instance plugins (future allowMultiple support)
    // this returns the first match — callers that care about specific
    // instances should iterate the section arrays directly.
    function settingFor(id, key, fallback) {
        const sections = [barLeft, barCenter, barRight];
        for (const sec of sections) {
            for (const entry of sec) {
                if (entry && entry.id === id) {
                    const v = entry[key];
                    return (v === undefined || v === null) ? fallback : v;
                }
            }
        }
        return fallback;
    }

    // ---- File watcher ----
    property FileView _file: FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text() || "{}");
                if (typeof parsed.version === "number" && parsed.version >= 1) {
                    root.data = parsed;
                    root.valid = true;
                } else {
                    console.warn("Config: shell.json missing or unsupported version");
                    root.data = ({});
                    root.valid = false;
                }
            } catch (e) {
                console.warn("Config: bad shell.json:", e);
                root.data = ({});
                root.valid = false;
            }
        }
        onLoadFailed: {
            root.data = ({});
            root.valid = false;
        }
        onFileChanged: reload()
    }
}
