import QtQuick
import qs

// Keyboard-layout indicator. Shows a short code for the active XKB
// layout (US, DE, …); click cycles to the next via niri's switch-layout
// action. NiriService keeps `keyboardLayouts` reactive off the niri
// event stream, so this just renders state — no polling.
//
// The widget collapses to zero width when only one layout is configured:
// a layout indicator is noise when there's nothing to switch to.
Item {
    id: root

    property var barWindow: null

    readonly property var names: NiriService.keyboardLayouts.names || []
    readonly property bool multi: names.length > 1

    // No bar real estate when there's nothing to toggle.
    visible: multi
    implicitHeight: Theme.barHeight
    implicitWidth:  multi ? pill.implicitWidth : 0

    // niri only exposes display names ("English (US)", "German"), not the
    // xkb codes — so map the common ones, then fall back to the code in
    // parentheses, then the first two letters.
    function shortName(name) {
        if (!name) return "??";
        var map = {
            "English (US)": "US", "English (UK)": "UK", "English (intl., with dead keys)": "US",
            "German":       "DE", "French":       "FR", "Spanish": "ES",
            "Italian":      "IT", "Russian":      "RU", "Polish":  "PL",
            "Portuguese":   "PT", "Dutch":        "NL", "Swedish": "SE",
            "Norwegian":    "NO", "Danish":       "DK", "Finnish": "FI",
            "Czech":        "CZ", "Turkish":      "TR", "Japanese": "JP"
        };
        if (map[name]) return map[name];
        var paren = name.match(/\(([A-Za-z]{2,3})\)/);
        if (paren) return paren[1].toUpperCase();
        return name.slice(0, 2).toUpperCase();
    }

    BarPill {
        id: pill
        tooltipText: I18n.t("keyboard-layout.tooltip") + ": " + NiriService.currentLayoutName
        onClicked: NiriService.runAction("switch-layout", "next")

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.shortName(NiriService.currentLayoutName)
            color: Theme.fg
            font.family: Theme.sansFamily
            font.pixelSize: Theme.barFontPx
            font.weight: Font.Medium
        }
    }
}
