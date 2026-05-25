import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Port of Omarchy's systemStats.qml.
// Bar shows the chip icon (󰍛). Left-click opens a popup with CPU / Memory /
// Load averaged over a 30-sample sparkline; right-click launches btop.
// Omarchy-only bits dropped: WidgetButton/PopupCard/DetailStat UI kit.
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

    function pushHistory(arr, value) {
        const next = arr.slice();
        next.push(value);
        if (next.length > historyLimit) next.shift();
        return next;
    }

    function refresh() {
        if (!statsProc.running) statsProc.running = true;
    }

    // The bar pill is a static chip glyph — sparkline / numbers only
    // appear inside the popup. So idle CPU is pure waste: poll fast
    // (2 s) while the popup is open, off otherwise. First open shows
    // current values with an empty sparkline; history fills as the
    // user keeps the popup up.
    Timer {
        interval: 2000
        running:  popover.popupOpen
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
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked: {
            popover.toggle();
            if (popover.popupOpen) root.refresh();
        }
        onRightClicked: {
            popover.close();
            root.launchOrFocusBtop();
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍛"   // nf-md-chip
            color: Theme.fg
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    // ---------------- Popup ----------------
    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  340
        implicitHeight: detailColumn.implicitHeight + 2 * contentMargin

        Column {
            id: detailColumn
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:     "󰍛"
                title:    I18n.t("stats.system")
                subtitle: I18n.t("stats.load") + " " + root.loadAvg.toFixed(2)
            }

            PopoverDivider {}

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

            PopoverDivider {}

            PopoverActions {
                PopoverButton {
                    label: "btop"
                    variant: PopoverButton.Primary
                    onTriggered: {
                        popover.close();
                        root.launchOrFocusBtop();
                    }
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
