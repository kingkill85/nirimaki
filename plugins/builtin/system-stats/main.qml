import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Port of Omarchy's systemStats.qml.
// Bar shows the chip icon (󰍛). Hover for a popup with CPU / Memory / Load
// averaged over a 30-sample sparkline. Omarchy-only bits dropped: btop
// launcher, WidgetButton/PopupCard/DetailStat UI kit.
Item {
    id: root

    property var barWindow: null

    // ---- Stats state ----
    property real cpuPercent: 0
    property real memPercent: 0
    property real loadAvg:    0
    property var  cpuHistory: []
    property var  memHistory: []
    property var  prevCpu: ({ idle: 0, total: 0 })
    readonly property int historyLimit: 30

    // ---- Hover-popup coordination (matches Omarchy 220 ms grace) ----
    property bool popupOpen:     false
    property bool buttonHovered: false
    property bool popupHovered:  false

    function pushHistory(arr, value) {
        const next = arr.slice();
        next.push(value);
        if (next.length > historyLimit) next.shift();
        return next;
    }

    function refresh() {
        if (!statsProc.running) statsProc.running = true;
    }

    function showPopup()    { hideTimer.stop(); popupOpen = true; }
    function scheduleHide() { hideTimer.restart(); }

    onButtonHoveredChanged: buttonHovered ? showPopup() : scheduleHide()
    onPopupHoveredChanged:  popupHovered  ? hideTimer.stop() : scheduleHide()

    // The bar pill is a static chip glyph — sparkline / numbers only
    // appear inside the popup. So idle CPU is pure waste: poll fast
    // (2 s) while the popup is open, off otherwise. First open shows
    // current values with an empty sparkline; history fills as the
    // user keeps the popup up.
    onPopupOpenChanged: if (popupOpen) refresh()

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: {
            if (!root.buttonHovered && !root.popupHovered) root.popupOpen = false;
        }
    }

    Timer {
        interval: 2000
        running:  root.popupOpen
        repeat:   true
        onTriggered: root.refresh()
    }

    // ---- procfs reader ----
    // Single bash invocation reads all three procfs files and emits a
    // delimiter-separated payload. Pre-refactor this was three separate
    // Process { command: ["bash", "-lc", ...] } objects = 6 forks per
    // tick (bash + tool). One bash, three sources, parsed below.
    // `-c` instead of `-lc` — the login-shell -l sourced profiles on
    // every poll for no benefit.
    Process {
        id: statsProc
        command: ["bash", "-c",
            "{ head -n1 /proc/stat; echo '---'; head -n3 /proc/meminfo; echo '---'; cat /proc/loadavg; }"]
        stdout: StdioCollector {
            id: statsOut
            waitForEnd: true
            onStreamFinished: {
                const parts = String(statsOut.text || "").split("---\n");
                if (parts.length < 3) return;

                // CPU
                const fields = parts[0].trim().split(/\s+/);
                if (fields.length >= 8) {
                    const user    = parseInt(fields[1]) || 0;
                    const nice    = parseInt(fields[2]) || 0;
                    const sys     = parseInt(fields[3]) || 0;
                    const idle    = parseInt(fields[4]) || 0;
                    const iowait  = parseInt(fields[5]) || 0;
                    const irq     = parseInt(fields[6]) || 0;
                    const softirq = parseInt(fields[7]) || 0;
                    const total = user + nice + sys + idle + iowait + irq + softirq;
                    const totalDiff = total - root.prevCpu.total;
                    const idleDiff  = idle  - root.prevCpu.idle;
                    if (root.prevCpu.total > 0 && totalDiff > 0) {
                        const usage = (1 - idleDiff / totalDiff) * 100;
                        root.cpuPercent = Math.max(0, Math.min(100, usage));
                        root.cpuHistory = root.pushHistory(root.cpuHistory, root.cpuPercent);
                    }
                    root.prevCpu = { idle: idle, total: total };
                }

                // Memory
                const memLines = parts[1].split("\n");
                let memTotal = 0, memAvailable = 0;
                for (const line of memLines) {
                    if (line.indexOf("MemTotal:") === 0)
                        memTotal = parseInt(line.replace(/[^0-9]/g, "")) || 0;
                    else if (line.indexOf("MemAvailable:") === 0)
                        memAvailable = parseInt(line.replace(/[^0-9]/g, "")) || 0;
                }
                if (memTotal > 0) {
                    root.memPercent = ((memTotal - memAvailable) / memTotal) * 100;
                    root.memHistory = root.pushHistory(root.memHistory, root.memPercent);
                }

                // Load average
                const n = parseFloat(parts[2].trim().split(/\s+/)[0]);
                if (!isNaN(n)) root.loadAvg = n;
            }
        }
    }

    // Btop launcher / focuser — delegates to NiriService.launchTui.
    function launchOrFocusBtop() { NiriService.launchTui("btop"); }

    // ---------------- Bar trigger ----------------
    implicitHeight: Theme.barHeight
    implicitWidth:  pill.width

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width:  iconText.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color: (root.buttonHovered || root.popupOpen) ? Theme.hot : "transparent"

        Text {
            id: iconText
            anchors.centerIn: parent
            text: "󰍛"   // nf-md-chip
            color: Theme.fg
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: root.buttonHovered = hovered
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.popupOpen = false;
                root.launchOrFocusBtop();
            }
        }
    }

    // ---------------- Popup ----------------
    PopupWindow {
        id: popup
        visible: root.popupOpen
        // Transparent window; the bordered card is the inner Rectangle.
        color: "transparent"

        // Drop directly under the pill, horizontally centred. `popupX`
        // is recomputed on every show because `mapToItem` isn't
        // binding-reactive (see Calendar.qml).
        property real popupX: 0
        anchor.window: root.barWindow
        anchor.rect.x: popupX
        anchor.rect.y: root.barWindow ? root.barWindow.height : 0

        onVisibleChanged: {
            if (visible) {
                popupX = pill.mapToItem(root.barWindow.contentItem, 0, 0).x
                       + (pill.width - implicitWidth) / 2;
                PopupBus.show(root);
            } else {
                PopupBus.hide(root);
            }
        }

        implicitWidth:  340
        implicitHeight: detailColumn.implicitHeight + 24

        HoverHandler {
            onHoveredChanged: root.popupHovered = hovered
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: Theme.cardBorderWidth
        }

        Column {
            id: detailColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: I18n.t("stats.system")
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                font.bold: true
            }

            DetailStat {
                title:   I18n.t("stats.cpu")
                value:   Math.round(root.cpuPercent) + "%"
                history: root.cpuHistory
                width: parent.width
            }

            DetailStat {
                title:   I18n.t("stats.memory")
                value:   Math.round(root.memPercent) + "%"
                history: root.memHistory
                width: parent.width
            }

            Row {
                width: parent.width
                spacing: 6
                Text {
                    text: I18n.t("stats.load")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                }
                Text {
                    text: root.loadAvg.toFixed(2)
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                }
            }
        }
    }

    // ---------------- DetailStat sub-component (title + value + sparkline) ----------------
    component DetailStat: Column {
        id: detail

        property string title:   ""
        property string value:   ""
        property var    history: []

        spacing: 4

        Item {
            width: detail.width
            height: titleText.implicitHeight

            Text {
                id: titleText
                anchors.left: parent.left
                text: detail.title
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
            Text {
                anchors.right: parent.right
                text: detail.value
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
        }

        Canvas {
            width:  parent.width
            height: 40
            property var history: detail.history
            onHistoryChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (!detail.history || detail.history.length === 0) return;

                const fg = Theme.fg;
                ctx.strokeStyle = fg;
                ctx.fillStyle   = Qt.rgba(fg.r, fg.g, fg.b, 0.22);
                ctx.lineWidth   = 1.5;

                ctx.beginPath();
                const step = width / Math.max(1, detail.history.length - 1);
                for (let i = 0; i < detail.history.length; i++) {
                    const x = i * step;
                    const y = height - (detail.history[i] / 100) * (height - 2) - 1;
                    if (i === 0) ctx.moveTo(x, y);
                    else         ctx.lineTo(x, y);
                }
                ctx.stroke();
                ctx.lineTo(width, height);
                ctx.lineTo(0, height);
                ctx.closePath();
                ctx.fill();
            }
        }
    }
}
