import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// On-screen display bezel — ported from Omarchy's shell/plugins/osd/Osd.qml
// (basecamp/omarchy@omarchy-shell). IPC-driven: external scripts invoke
//
//   quickshell ipc call osd show '<json payload>'
//
// after they've changed the underlying state (volume, brightness, mic, …).
// Payload keys: icon, message, value, max, progressText. See bin/nirimaki-osd
// for the convenience wrapper and bin/nirimaki-audio-* for callers.
//
// Deviations from upstream:
//   - qs.Commons → Theme.qml
//   - Color.alpha(c,a) → Qt.rgba(c.r, c.g, c.b, a)
//   - "JetBrainsMono Nerd Font" → Theme.iconFamily / Theme.sansFamily
//     (this shell uses the no-ligature NL variant via Theme).
//   - One PanelWindow per screen via Variants (was single-window before,
//     which meant the bezel only ever appeared on the first/"primary"
//     monitor — bad UX on multi-monitor setups where the user is looking
//     elsewhere when adjusting volume).
Item {
    id: root

    property bool opened: false
    property string icon: ""
    property string message: ""
    property int value: 0
    property int maxValue: 100
    property bool hasProgress: true

    function clamp(v, min, max) { return Math.max(min, Math.min(max, v)) }

    function iconFor(name, percent) {
        const n = String(name || "").toLowerCase();
        if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return "󰝟";
        if (n === "volume-low")    return "󰕿";
        if (n === "volume-medium") return "󰖀";
        if (n === "volume-high" || n === "volume") return "󰕾";
        if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭";
        if (n === "microphone" || n === "mic") return "󰍬";
        if (n === "keyboard") return "󰌌";
        if (n === "brightness" || n === "display") return "󰃠";
        if (n === "touchpad") return "󰟸";
        if (n === "touch" || n === "touchscreen") return "󰜉";
        if (n === "media" || n === "player") return "󰝚";
        if (percent <= 0)  return "󰝟";
        if (percent <= 33) return "󰕿";
        if (percent <= 66) return "󰖀";
        return "󰕾";
    }

    function show(iconName, rawMessage, rawValue, rawMax, rawProgressText) {
        maxValue = Math.max(1, parseInt(rawMax || "100", 10));
        const parsed = parseInt(rawValue || "0", 10);
        hasProgress = rawValue !== "" && !isNaN(parsed) && rawMessage === "";
        value = hasProgress ? clamp(parsed, 0, maxValue) : 0;
        message = String(rawMessage || (hasProgress
            ? (rawProgressText || Math.round(value * 100 / maxValue) + "%")
            : ""));
        icon = iconFor(iconName, hasProgress ? Math.round(value * 100 / maxValue) : -1);
        opened = true;
        hideTimer.restart();
    }

    function open(payloadJson) {
        try {
            const p = JSON.parse(payloadJson || "{}");
            show(p.icon || "",
                 p.message || "",
                 p.value === undefined ? "" : String(p.value),
                 p.max === undefined ? "100" : String(p.max),
                 p.progressText || "");
        } catch (e) {}
    }

    function closeOsd() { opened = false }

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: root.opened = false
    }

    IpcHandler {
        target: "osd"
        function show(payloadJson: string): string {
            root.open(payloadJson); return "ok"
        }
        function close(): string { root.closeOsd(); return "ok" }
        function state(): string { return root.opened ? "open" : "closed" }
        function ping(): string  { return "ok" }
    }

    Variants {
        model: Quickshell.screens
    delegate: PanelWindow {
        id: panel
        required property ShellScreen modelData
        screen: modelData
        visible: root.opened
        // Anchor to bottom only — wlr-layer-shell auto-centres the
        // unanchored (horizontal) axis. Sizing the surface to the bezel
        // (269×68) instead of full-screen keeps niri's blur layer-rule
        // (matches `^(quickshell|nirimaki-.*)$`) scoped to the bezel
        // backdrop, not the whole monitor.
        anchors.bottom: true
        margins.bottom: 67
        implicitWidth:  269
        implicitHeight: 68
        color: "transparent"
        WlrLayershell.namespace: "nirimaki-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
            border.color: Theme.fg
            border.width: 2
            radius: Theme.radius
            opacity: root.opened ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 16

                Text {
                    width: 28
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.icon
                    font.family: Theme.iconFamily
                    font.pixelSize: 27
                    color: Theme.fg
                }

                Rectangle {
                    visible: root.hasProgress
                    width: visible ? 142 : 0
                    height: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.45)

                    Rectangle {
                        height: parent.height
                        width: parent.width *
                            (root.hasProgress ? root.value / root.maxValue : 0)
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Text {
                    width: root.hasProgress ? 41 : 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.message
                    font.family: Theme.sansFamily
                    font.bold: true
                    font.pixelSize: Theme.fontPxMedium
                    color: Theme.fg
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    clip: true
                }
            }
        }
    }
    }
}
