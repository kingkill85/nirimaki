import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Ethernet status widget. Polls `ip route` + /sys/class/net every 3 s.
// Click → small read-only popup with IP / gateway / link speed.
// No TUI launch — Ethernet on systemd-networkd has nothing actionable
// at runtime; configuration is file-based.
Item {
    id: root

    property var barWindow: null

    // Parsed state from the polling script
    property var info: ({})      // { state, iface, ip, gateway, speed, duplex }

    readonly property bool connected: info.state === "connected"
    readonly property string icon:
        connected ? "󰈀"   // nf-md-ethernet
                  : "󰈂"   // nf-md-ethernet_off

    function refresh() { if (!netProc.running) netProc.running = true }

    Component.onCompleted: refresh()

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: netProc
        command: ["bash", "-c", `
device=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
if [[ -z $device ]]; then
  printf 'state\\tdisconnected\\n'
  exit 0
fi
# One ip route get, parse everything from its output (was three forks pre-refactor).
route=$(ip route get 1.1.1.1 2>/dev/null)
src=$(awk '{ for (i=1;i<=NF;i++) if ($i=="src") { print $(i+1); exit } }' <<<"$route")
gw=$(awk '{ for (i=1;i<=NF;i++) if ($i=="via") { print $(i+1); exit } }' <<<"$route")
prefix=$(ip -o -f inet addr show "$device" 2>/dev/null | awk '{ split($4,a,"/"); print a[2]; exit }')
printf 'state\\tconnected\\n'
printf 'iface\\t%s\\n' "$device"
[[ -n $src ]] && printf 'ip\\t%s/%s\\n' "$src" "$prefix"
[[ -n $gw ]] && printf 'gateway\\t%s\\n' "$gw"
if [[ -r /sys/class/net/$device/speed ]]; then
  speed=$(cat /sys/class/net/$device/speed 2>/dev/null)
  [[ -n $speed && $speed -gt 0 ]] && printf 'speed\\t%s Mbps\\n' "$speed"
fi
if [[ -r /sys/class/net/$device/duplex ]]; then
  dup=$(cat /sys/class/net/$device/duplex 2>/dev/null)
  [[ -n $dup && $dup != unknown ]] && printf 'duplex\\t%s\\n' "$dup"
fi
`]
        stdout: StdioCollector {
            id: netOut
            waitForEnd: true
            onStreamFinished: {
                const next = {};
                const lines = String(netOut.text || "").split("\n");
                for (const line of lines) {
                    if (!line) continue;
                    const idx = line.indexOf("\t");
                    if (idx === -1) continue;
                    next[line.substring(0, idx)] = line.substring(idx + 1).trim();
                }
                root.info = next;
            }
        }
    }

    // ---------------- Bar trigger ----------------
    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked: popover.toggle()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.connected ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    // ---------------- Popup ----------------
    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  260
        implicitHeight: content.implicitHeight + 2 * contentMargin

        Column {
            id: content
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:      root.icon
                iconColor: root.connected ? Theme.fg : Theme.fgDim
                title:     root.info.iface
                           || (root.connected ? "" : I18n.t("network.disconnected"))
                subtitle:  root.connected ? I18n.t("network.ethernet") : ""
            }

            PopoverDivider { visible: root.connected }

            Grid {
                columns: 2
                columnSpacing: 14
                rowSpacing: 4
                width: parent.width
                visible: root.connected

                Text { text: I18n.t("network.ip");       color: Theme.fgDim; font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2; visible: !!root.info.ip }
                Text { text: root.info.ip || ""; color: Theme.fg; font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2; visible: !!root.info.ip }

                Text { text: I18n.t("network.gateway");  color: Theme.fgDim; font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2; visible: !!root.info.gateway }
                Text { text: root.info.gateway || ""; color: Theme.fg; font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2; visible: !!root.info.gateway }

                Text { text: I18n.t("network.link");     color: Theme.fgDim; font.family: Theme.sansFamily; font.pixelSize: Theme.fontPx - 2; visible: !!root.info.speed }
                Text {
                    text: (root.info.speed || "") + (root.info.duplex ? "  ·  " + root.info.duplex + " " + I18n.t("network.duplex") : "")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    visible: !!root.info.speed
                }
            }
        }
    }
}
