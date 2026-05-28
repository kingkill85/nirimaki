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

        implicitWidth:  280
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon: root.muted ? "󰝟"
                    : (root.volume > 0.66 ? "󰕾"
                       : root.volume > 0.33 ? "󰖀" : "󰕿")
                iconColor: root.muted ? Theme.fgDim : Theme.fg
                title:    root.sinkName || "—"
                subtitle: root.muted
                    ? I18n.t("audio.muted")
                    : Math.round(root.volume * 100) + "%"
            }

            PopoverDivider {}

            PanelSlider {
                width: parent.width
                value: root.volume
                onMoved:    (v) => AudioService.setVolume(AudioService.defaultSink, v)
                onReleased: (v) => AudioService.setVolume(AudioService.defaultSink, v)
            }

            PopoverDivider {}

            PopoverActions {
                PopoverButton {
                    label: root.muted ? I18n.t("audio.unmute") : I18n.t("audio.mute")
                    variant: root.muted ? PopoverButton.Urgent : PopoverButton.Secondary
                    onTriggered: AudioService.toggleMute(AudioService.defaultSink)
                }
                PopoverButton {
                    label: I18n.t("audio.bar.mixer")
                    variant: PopoverButton.Primary
                    onTriggered: root.openMixer()
                }
            }
        }
    }
}
