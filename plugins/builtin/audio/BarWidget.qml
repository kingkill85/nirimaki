import QtQuick
import qs

// Default-sink audio widget.
//   Left click     → toggle compact popover (slider + mute + mixer link)
//   Right click    → summon the full audio mixer panel
//   Scroll up/down → adjust default-sink volume by 5 %
// State comes from AudioService — no inline Pipewire wiring here.
Item {
    id: root

    property var barWindow: null

    readonly property real volume:    AudioService.defaultSinkVolume
    readonly property bool muted:     AudioService.defaultSinkMuted
    readonly property string sinkName: AudioService.displayName(AudioService.defaultSink)

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    function openMixer() {
        popover.close();
        Plugins.summon("audio");
    }

    BarPill {
        id: pill
        active: popover.popupOpen
        tooltipText: root.muted
            ? I18n.t("audio.tooltip_muted")
            : I18n.t("audio.tooltip").replace("{0}", Math.round(root.volume * 100))
        onClicked:      popover.toggle()
        onRightClicked: root.openMixer()
        onWheel: (ticks) => AudioService.adjustDefaultSink(ticks * 0.05)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Material Design Icons via Nerd Font
            //   muted   nf-md-volume_mute    󰝟
            //   high    nf-md-volume_high    󰕾
            //   medium  nf-md-volume_medium  󰖀
            //   low     nf-md-volume_low     󰕿
            text: root.muted
                  ? "󰝟"
                  : (root.volume > 0.66
                     ? "󰕾"
                     : (root.volume > 0.33
                        ? "󰖀"
                        : "󰕿"))
            color: Theme.fg
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
        // Icon-only in the bar (Omarchy parity). The level lives in the
        // tooltip + popover header; muted state reads from the glyph (󰝟).
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  300
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            // Family header — glanceable out/in summary; icon mirrors output.
            PopoverHeader {
                icon: root.muted ? "󰝟"
                    : (root.volume > 0.66 ? "󰕾" : root.volume > 0.33 ? "󰖀" : "󰕿")
                iconColor: root.muted ? Theme.fgDim : Theme.fg
                title:    I18n.t("audio.title")
                subtitle: {
                    const out = root.muted ? I18n.t("audio.muted")
                                           : Math.round(root.volume * 100) + "%";
                    if (!AudioService.defaultSource) return out;
                    const inp = AudioService.defaultSourceMuted
                                ? I18n.t("audio.muted")
                                : Math.round(AudioService.defaultSourceVolume * 100) + "%";
                    return out + "   ·   󰍬 " + inp;
                }
            }

            PopoverDivider {}

            // Output (default sink) — always present.
            DeviceSection {
                width:   parent.width
                label:   I18n.t("audio.tab.output")
                node:    AudioService.defaultSink
                deviceName: root.sinkName
                volume:  AudioService.defaultSinkVolume
                muted:   AudioService.defaultSinkMuted
                isInput: false
            }

            PopoverDivider { visible: inputSection.visible }

            // Input (default source) — only when a capture device exists.
            DeviceSection {
                id: inputSection
                width:   parent.width
                visible: !!AudioService.defaultSource
                label:   I18n.t("audio.tab.input")
                node:    AudioService.defaultSource
                deviceName: AudioService.displayName(AudioService.defaultSource)
                volume:  AudioService.defaultSourceVolume
                muted:   AudioService.defaultSourceMuted
                isInput: true
            }

            PopoverDivider {}

            PopoverActions {
                PopoverButton {
                    label: I18n.t("audio.bar.mixer")
                    variant: PopoverButton.Primary
                    onTriggered: root.openMixer()
                }
            }
        }
    }

    // ---------------- DeviceSection — label + (mute-icon · name · %) + slider ----------------
    // The leading icon doubles as a click-to-mute toggle: it shows the
    // current level/mute glyph and dims when muted.
    component DeviceSection: Column {
        id: sec

        property var    node:       null
        property string label:      ""
        property string deviceName: ""
        property real   volume:     0
        property bool   muted:      false
        property bool   isInput:    false

        spacing: 6

        function glyph() {
            if (sec.isInput)
                return sec.muted ? "󰍭" : "󰍬";          // mic-off / mic
            return sec.muted ? "󰝟"                      // volume-mute
                : (sec.volume > 0.66 ? "󰕾"              // high
                   : sec.volume > 0.33 ? "󰖀" : "󰕿");    // medium / low
        }

        // Small dim section label ("Output" / "Input").
        Text {
            text: sec.label
            color: Theme.fgDim
            font.family: Theme.sansFamily
            font.pixelSize: Theme.fontPx - 3
        }

        // Mute-icon · device name · percentage.
        Item {
            width: sec.width
            height: Math.max(iconText.implicitHeight, nameText.implicitHeight, pctText.implicitHeight)

            Text {
                id: iconText
                anchors.verticalCenter: parent.verticalCenter
                text: sec.glyph()
                color: sec.muted ? Theme.fgDim : Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AudioService.toggleMute(sec.node)
                }
            }
            Text {
                id: nameText
                anchors.left: iconText.right
                anchors.leftMargin: 8
                anchors.right: pctText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: sec.deviceName || "—"
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 1
                elide: Text.ElideRight
            }
            Text {
                id: pctText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: sec.muted ? I18n.t("audio.muted")
                                : Math.round(sec.volume * 100) + "%"
                color: sec.muted ? Theme.fgDim : Theme.fg
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontPx - 1
            }
        }

        PanelSlider {
            width: sec.width
            value: sec.volume
            opacity: sec.muted ? 0.5 : 1.0
            onMoved:    (v) => AudioService.setVolume(sec.node, v)
            onReleased: (v) => AudioService.setVolume(sec.node, v)
        }

        // Quick mute toggle (the leading icon also toggles mute).
        Button {
            width: sec.width
            label: sec.muted ? I18n.t("audio.unmute") : I18n.t("audio.mute")
            variant: sec.muted ? Button.Urgent : Button.Secondary
            onTriggered: AudioService.toggleMute(sec.node)
        }
    }
}
