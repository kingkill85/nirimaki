pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Theme singleton — palette comes from ~/.config/theme/current/{colors,
// shell}.toml. Both files are FileView-watched, so `nirimaki-theme-set <name>`
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

    // Translucent card fill — used by every overlay / popup / picker.
    // The bar itself stays opaque (it's a strip, not a card). Alpha
    // 0.95 matches Omarchy's walker.css `background: alpha(@base, 0.95)`:
    // wallpaper hue is faintly visible without eating contrast.
    readonly property real  cardAlpha: 0.95
    readonly property color cardBg:    Qt.rgba(bg.r, bg.g, bg.b, cardAlpha)
    // Every overlay card gets a 2 px accent-coloured border so the
    // visual matches niri's focused-window border (also `accent`).
    // Omarchy's walker uses foreground here, but we prioritise
    // compositor↔shell consistency over a literal Omarchy port.
    readonly property int   cardBorderWidth: 2
    readonly property color cardBorderColor: accent

    // ===== Per-surface map (loaded from shell.toml; "<section>.<key>") =====
    property var shellValues: ({})

    function pick(key, fallback) {
        const v = shellValues[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    // ===== Sizing tokens =====
    readonly property int barHeight:   26
    readonly property int padX:        10
    readonly property int padY:        4
    readonly property int gap:         6
    // Square-corner everything (Omarchy parity). Kept as a token so any
    // future "soft round" theme can flip it in one place.
    readonly property int radius:      0
    readonly property int focusBorder: 3
    readonly property int fontPx:      13
    readonly property int iconPx:      15
    // Bar-label text size. Held one notch below `fontPx` so the topbar
    // reads as compact as Omarchy's waybar (font-size: 12px) without
    // shrinking popovers / menus, which stay on `fontPx`.
    readonly property int barFontPx:   12
    // Extra font-size tokens. `fontPx` (13) is the popup body
    // size; the others cover sub-labels (small), secondary text
    // (medium), and the picker / launcher row text (large = 18 px, to
    // match Omarchy walker's `font-size: 18px`).
    readonly property int fontPxSmall:  10
    readonly property int fontPxMedium: 14
    readonly property int fontPxLarge:  18

    // ===== Menu / picker sizing =====
    // Every full-screen overlay (Launcher, PowerMenu, EmojiPicker,
    // ClipboardPicker, future Theme/Background pickers …) reads these
    // tokens so they share margins, row heights, header style etc.
    // Change here → every menu updates. Per-overlay differences
    // (cardWidth/Height, icon size for content-specific glyphs) stay
    // local because they're inherently different sizes of *content*.
    readonly property int menuMargin:        18  // padding inside card
    readonly property int menuSpacing:       10  // between header & list
    readonly property int menuHeaderHeight:  34  // search / title row
    readonly property int menuRowHeight:     50  // each list item
    readonly property int menuRowSpacing:    3   // between items
    readonly property int menuFontPx:        fontPxLarge   // 18
    readonly property int menuIconPx:        fontPxLarge + 2  // 20

    // ===== Bar popover tokens =====
    // Every bar popover uses the same Header / Divider / Body / Actions
    // shape. These are the shared layout numbers — change here to
    // re-tune the whole family. Per-popover paddings stay local via
    // BarPopover.contentMargin (default 12).
    readonly property int popoverSpacing:        10   // between sections
    readonly property int popoverHeaderIconPx:   22   // big icon in header
    readonly property int popoverHeaderRowHeight: 30  // header row minimum height (icon-sized)
    readonly property int popoverButtonHeight:   30   // action button height
    readonly property int popoverButtonSpacing:  8    // between action buttons

    // ===== Control tokens (Group A UI kit) =====
    // Shared geometry for Toggle / PanelSlider / Dropdown / TextField /
    // Button. Single source of truth for the kit so a whole-theme tweak
    // is one file. Anything popover-specific stays under the popover*
    // block above; anything here applies to controls used in panels,
    // popovers, settings forms, dialogs alike.
    readonly property int controlHeight:           32   // text fields, dropdown header, single-row toggle
    readonly property int controlPadX:             10   // horizontal padding inside controls
    readonly property int controlBorderWidth:      1
    readonly property int controlFocusBorderWidth: 2
    readonly property int controlSpacing:          8    // between stacked controls

    // Slider (PanelSlider). Knob scales subtly on hover/drag (see primitive).
    readonly property int sliderTrackHeight:  4
    readonly property int sliderKnobSize:     14

    // Toggle switch geometry. Pill shape derived from track height.
    readonly property int toggleTrackHeight:  22
    readonly property int toggleTrackWidth:   42
    readonly property int toggleKnobSize:     16
    readonly property int toggleKnobInset:    3

    // Dropdown popup geometry.
    readonly property int dropdownRowHeight:  30
    readonly property int dropdownMaxRows:    8    // before scrolling

    // Tooltip — small contextual label after hover dwell.
    readonly property int tooltipDelay:  600        // ms
    readonly property int tooltipPadX:   8
    readonly property int tooltipPadY:   4
    readonly property int tooltipFontPx: fontPx - 2

    // ===== Fonts =====
    // Family resolves from ~/.config/nirimaki/font (one family name per
    // line, written by `nirimaki font set`). Default JetBrainsMono Nerd
    // Font when the file is missing or empty. FileView watches the file
    // so font changes apply live without restarting Quickshell.
    property string monoFamily: "JetBrainsMono Nerd Font"
    property string sansFamily: "JetBrainsMono Nerd Font"
    property string iconFamily: "JetBrainsMono Nerd Font"

    function _applyFont(raw) {
        const family = String(raw || "").trim().split("\n")[0];
        const f = family || "JetBrainsMono Nerd Font";
        monoFamily = f;
        sansFamily = f;
        iconFamily = f;
    }

    property FileView _fontFile: FileView {
        path: Quickshell.env("HOME") + "/.config/nirimaki/font"
        watchChanges: true
        printErrors: false
        onLoaded:      root._applyFont(text())
        onFileChanged: reload()
        onLoadFailed:  root._applyFont("")
    }

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

    // ===== Live theme metadata =====
    // True when the active theme has NO light.mode file (Omarchy
    // convention: presence = light, absence = dark).
    property bool isDark: true
    // Current theme name (default "default" if theme.name absent).
    property string themeName: "default"

    // Manual reload trigger. `nirimaki-theme-set` calls
    //   quickshell ipc call -- theme reload
    // after it rewrites the theme files, because inotify-based file
    // watches race against `cp` (truncate-then-write fires onFileChanged
    // while the file is still empty, then no second event when the
    // write finishes). Explicit IPC is reliable.
    function reload() {
        _colorsFile.reload();
        _shellFile.reload();
        _lightModeFile.reload();
        _themeNameFile.reload();
    }

    // IpcHandler must be attached via a property because QtObject has
    // no default child property.
    property IpcHandler _ipc: IpcHandler {
        target: "theme"
        function reload(): string { root.reload(); return "ok" }
        function ping(): string   { return "ok" }
    }

    // FileViews remain as a fallback for theme changes that happen
    // outside nirimaki-theme-set (e.g. editing colors.toml by hand). The
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

    // Empty marker file: present → light theme.
    property FileView _lightModeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/theme/current/light.mode"
        watchChanges: true
        printErrors: false
        onLoaded:      root.isDark = false
        onFileChanged: reload()
        onLoadFailed:  root.isDark = true
    }

    property FileView _themeNameFile: FileView {
        path: Quickshell.env("HOME") + "/.config/theme/current/theme.name"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = String(text() || "").trim();
            if (t.length > 0) root.themeName = t;
        }
        onFileChanged: reload()
        onLoadFailed: root.themeName = "default"
    }
}
