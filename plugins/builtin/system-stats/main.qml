import QtQuick
import Quickshell
import Quickshell.Io
import qs

// System-stats bar widget. The pill is a static chip glyph (󰍛); left-click
// opens a popover with a fastfetch-style identity header plus live CPU / GPU /
// memory / disk readouts; right-click launches btop.
//
// Two readers feed the popover:
//   infoProc  — one-shot, run once on first open. Static facts that never
//               change during a session (CPU/GPU model, core counts, OS,
//               kernel, host). Polling these would be pure waste.
//   statsProc — the 2 s poll loop (gated on popupOpen). One bash invocation
//               reads every dynamic source and emits `---`-delimited sections.
Item {
    id: root

    property var barWindow: null

    // ---- Static info (infoProc, loaded once) ----
    property bool   infoLoaded:  false
    property string cpuModel:    ""
    property string gpuModel:    ""
    property string coresLabel:  ""   // "8c/16t"
    property string osName:      ""
    property string kernel:      ""
    property string host:        ""

    // ---- Dynamic stats (statsProc, 2 s while open) ----
    property real cpuPercent: 0
    property real cpuTemp:    0
    property real gpuPercent: 0
    property real gpuTemp:    0
    property real memUsed:    0   // bytes
    property real memTotal:   0   // bytes
    property real swapPercent: 0
    property real diskUsed:   0   // bytes
    property real diskTotal:  0   // bytes
    property real uptimeSec:  0
    property var  cpuHistory: []
    property var  gpuHistory: []
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
        if (!root.infoLoaded && !infoProc.running) infoProc.running = true;
    }

    // ---- Formatting helpers ----
    function gib(bytes) {
        if (!bytes || bytes <= 0) return "0G";
        return (bytes / 1073741824).toFixed(1) + "G";
    }
    function pct(used, total) {
        if (!total || total <= 0) return 0;
        return Math.max(0, Math.min(100, (used / total) * 100));
    }
    function fmtUptime(sec) {
        if (!sec || sec <= 0) return "";
        const d = Math.floor(sec / 86400);
        const h = Math.floor((sec % 86400) / 3600);
        const m = Math.floor((sec % 3600) / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }
    // Trim marketing noise from a raw CPU model string.
    function shortenCpu(s) {
        return String(s)
            .replace(/\(R\)|\(TM\)|\(tm\)/g, "")
            .replace(/\s+\d+-Core Processor/i, "")
            .replace(/\s+Processor/i, "")
            .replace(/\s+CPU.*$/i, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    Timer {
        interval: 2000
        running:  popover.popupOpen
        repeat:   true
        onTriggered: root.refresh()
    }

    // ---- Static info reader (one-shot) ----
    // Each fact on its own `---`-delimited line. /proc/cpuinfo for the CPU
    // model (locale-proof, unlike `lscpu`'s "Model name"); `lscpu -p` for the
    // physical-core count (`-p` is machine-readable so de_DE doesn't break it).
    Process {
        id: infoProc
        command: ["bash", "-c",
            "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//'; echo '---';" +
            "lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l; echo '---';" +
            "nproc; echo '---';" +
            "lspci -mm 2>/dev/null | grep -iE 'VGA|3D controller|Display controller' | head -n1; echo '---';" +
            ". /etc/os-release 2>/dev/null; echo \"${PRETTY_NAME:-${NAME:-Linux}}\"; echo '---';" +
            "uname -r; echo '---'; uname -n"]
        stdout: StdioCollector {
            id: infoOut
            waitForEnd: true
            onStreamFinished: {
                const p = String(infoOut.text || "").split("---\n");
                if (p.length < 7) return;
                root.cpuModel = root.shortenCpu(p[0].trim());

                const cores = parseInt(p[1].trim()) || 0;
                const threads = parseInt(p[2].trim()) || 0;
                root.coresLabel = (cores > 0 ? cores + "c" : "") +
                                  (threads > 0 ? "/" + threads + "t" : "");

                // lspci -mm: slot "Class" "Vendor" "Device" ... — Device is the
                // 3rd quoted token (index 5 after split on "). Prefer the
                // marketing name inside the last [...] when present.
                const lspci = p[3].trim();
                const q = lspci.split('"');
                let dev = q.length > 5 ? q[5] : lspci;
                const brk = dev.match(/\[([^\]]+)\]/);
                root.gpuModel = (brk ? brk[1] : dev).replace(/\s+/g, " ").trim();

                root.osName = p[4].trim();
                root.kernel = p[5].trim();
                root.host   = p[6].trim();
                root.infoLoaded = true;
            }
        }
    }

    // ---- Dynamic stats reader (single bash invocation) ----
    Process {
        id: statsProc
        command: ["bash", "-c",
            "head -n1 /proc/stat; echo '---';" +
            "grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo; echo '---';" +
            "for h in /sys/class/hwmon/*; do n=$(cat \"$h/name\" 2>/dev/null);" +
            " case \"$n\" in k10temp) echo \"cpu $(cat \"$h/temp1_input\" 2>/dev/null)\";;" +
            " amdgpu) echo \"gpu $(cat \"$h/temp1_input\" 2>/dev/null)\";; esac; done; echo '---';" +
            "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1; echo '---';" +
            "cut -d' ' -f1 /proc/uptime; echo '---';" +
            "df -B1 --output=used,size / 2>/dev/null"]
        stdout: StdioCollector {
            id: statsOut
            waitForEnd: true
            onStreamFinished: {
                const parts = String(statsOut.text || "").split("---\n");
                if (parts.length < 6) return;

                // [0] CPU — usage from idle/total delta vs the previous tick.
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

                // [1] Memory + swap (values in kB).
                let memTotal = 0, memAvailable = 0, swapTotal = 0, swapFree = 0;
                for (const line of parts[1].split("\n")) {
                    const v = parseInt(line.replace(/[^0-9]/g, "")) || 0;
                    if      (line.indexOf("MemTotal:")     === 0) memTotal     = v;
                    else if (line.indexOf("MemAvailable:") === 0) memAvailable = v;
                    else if (line.indexOf("SwapTotal:")    === 0) swapTotal    = v;
                    else if (line.indexOf("SwapFree:")     === 0) swapFree     = v;
                }
                if (memTotal > 0) {
                    root.memTotal = memTotal * 1024;
                    root.memUsed  = (memTotal - memAvailable) * 1024;
                }
                root.swapPercent = swapTotal > 0
                    ? ((swapTotal - swapFree) / swapTotal) * 100 : 0;

                // [2] Temperatures (millidegrees → °C), matched by hwmon name.
                for (const line of parts[2].split("\n")) {
                    const m = line.trim().split(/\s+/);
                    if (m.length < 2) continue;
                    const t = (parseInt(m[1]) || 0) / 1000;
                    if      (m[0] === "cpu") root.cpuTemp = t;
                    else if (m[0] === "gpu") root.gpuTemp = t;
                }

                // [3] GPU busy %.
                const gpu = parseInt(parts[3].trim());
                if (!isNaN(gpu)) {
                    root.gpuPercent = Math.max(0, Math.min(100, gpu));
                    root.gpuHistory = root.pushHistory(root.gpuHistory, root.gpuPercent);
                }

                // [4] Uptime (seconds).
                const up = parseFloat(parts[4].trim());
                if (!isNaN(up)) root.uptimeSec = up;

                // [5] Disk — `df --output=used,size` (fixed column order, so
                // the localized header is skipped and the data row parsed raw).
                const dfLines = parts[5].trim().split("\n");
                if (dfLines.length >= 2) {
                    const cols = dfLines[1].trim().split(/\s+/);
                    root.diskUsed  = parseInt(cols[0]) || 0;
                    root.diskTotal = parseInt(cols[1]) || 0;
                }
            }
        }
    }

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

        implicitWidth:  360
        implicitHeight: detailColumn.implicitHeight + 2 * contentMargin

        Column {
            id: detailColumn
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            // ---- Identity header ----
            Row {
                width: parent.width
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍛"
                    color: Theme.fg   // neutral — matches PopoverHeader family
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.popoverHeaderIconPx
                }
                Column {
                    width: parent.width - 10 - Theme.popoverHeaderIconPx
                    spacing: 1
                    Text {
                        text: (root.host || I18n.t("stats.system")) +
                              (root.uptimeSec > 0 ? "  ·  " + I18n.t("stats.uptime") + " " + root.fmtUptime(root.uptimeSec) : "")
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: [root.osName, root.kernel].filter(function (s) { return s; }).join("  ·  ")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text.length > 0
                    }
                }
            }

            PopoverDivider {}

            // ---- CPU / GPU (sparkline rows) ----
            StatRow {
                width: parent.width
                title:   I18n.t("stats.cpu")
                model:   root.cpuModel +
                         (root.coresLabel ? "  ·  " + root.coresLabel : "")
                value:   Math.round(root.cpuPercent) + "%"
                temp:    root.cpuTemp
                history: root.cpuHistory
            }

            StatRow {
                width: parent.width
                title:   I18n.t("stats.gpu")
                model:   root.gpuModel
                value:   Math.round(root.gpuPercent) + "%"
                temp:    root.gpuTemp
                history: root.gpuHistory
            }

            PopoverDivider {}

            // ---- Memory / disk (meter rows) ----
            MeterRow {
                width: parent.width
                title:    I18n.t("stats.memory")
                detail:   root.gib(root.memUsed) + " / " + root.gib(root.memTotal)
                fraction: root.pct(root.memUsed, root.memTotal) / 100
                subFraction: root.swapPercent / 100
            }

            MeterRow {
                width: parent.width
                title:    I18n.t("stats.disk") + "  /"
                detail:   root.gib(root.diskUsed) + " / " + root.gib(root.diskTotal)
                fraction: root.pct(root.diskUsed, root.diskTotal) / 100
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

    // ---------------- StatRow — title + dim model + value/temp + sparkline ----------------
    component StatRow: Column {
        id: stat

        property string title:   ""
        property string model:   ""
        property string value:   ""
        property real   temp:    0
        property var    history: []

        spacing: 4

        // Label line: title | model (dim, elastic) | value + temp
        Item {
            width: stat.width
            height: titleText.implicitHeight

            Text {
                id: titleText
                anchors.left: parent.left
                text: stat.title
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
            Text {
                anchors.left: titleText.right
                anchors.leftMargin: 8
                anchors.right: valueText.left
                anchors.rightMargin: 8
                text: stat.model
                color: Theme.fgDim
                opacity: 0.7
                elide: Text.ElideRight
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 3
            }
            Text {
                id: valueText
                anchors.right: parent.right
                text: stat.value +
                      (stat.temp > 0 ? "   " + Math.round(stat.temp) + "°" : "")
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
        }

        // Sparkline of the recent history (full width).
        Canvas {
            width:  stat.width
            height: 34
            property var history: stat.history
            onHistoryChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (!stat.history || stat.history.length === 0) return;

                const fg = Theme.accent;
                ctx.strokeStyle = fg;
                ctx.fillStyle   = Qt.rgba(fg.r, fg.g, fg.b, 0.22);
                ctx.lineWidth   = 1.5;

                ctx.beginPath();
                const step = width / Math.max(1, stat.history.length - 1);
                for (let i = 0; i < stat.history.length; i++) {
                    const x = i * step;
                    const y = height - (stat.history[i] / 100) * (height - 2) - 1;
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

    // ---------------- MeterRow — title + detail + percent + thin usage bar ----------------
    component MeterRow: Column {
        id: meter

        property string title:    ""
        property string detail:   ""   // "9.2G / 32.0G"
        property real   fraction: 0    // 0..1 primary fill
        property real   subFraction: -1 // 0..1 secondary (e.g. swap); <0 = none

        spacing: 4

        Item {
            width: meter.width
            height: mTitle.implicitHeight

            Text {
                id: mTitle
                anchors.left: parent.left
                text: meter.title
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
            Text {
                anchors.right: mPct.left
                anchors.rightMargin: 8
                text: meter.detail
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
            Text {
                id: mPct
                anchors.right: parent.right
                text: Math.round(meter.fraction * 100) + "%"
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 2
            }
        }

        // Track + fill. A second faint segment overlays swap usage when present.
        Rectangle {
            width: meter.width
            height: 6
            radius: 3
            color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.25)

            Rectangle {
                width: Math.max(0, Math.min(1, meter.fraction)) * parent.width
                height: parent.height
                radius: parent.radius
                color: Theme.accent
            }
            Rectangle {
                visible: meter.subFraction > 0
                width: Math.max(0, Math.min(1, meter.subFraction)) * parent.width
                height: 2
                anchors.bottom: parent.bottom
                radius: 1
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
            }
        }
    }
}
