import QtQuick

// Action-row button used in the footer of every BarPopover.
//
//   PopoverButton {
//       label:   "run update"
//       variant: PopoverButton.Primary
//       onTriggered: root.runUpdate()
//   }
//
// Two variants:
//   - Primary   — accent border + accent text + faint accent fill. For
//                 the "main" affordance the popover is built around
//                 (run update, open bluetui, ...).
//   - Secondary — fgDim border + fg text + faint fg fill. For neutral
//                 toggles (mute, turn off, …).
//   - Urgent    — urgent border + urgent text. For "destructive" or
//                 attention-grabbing affordances (unmute when muted,
//                 forget device, …).
//
// `enabled: false` dims to 0.4 opacity and disables the click.
Rectangle {
    id: root

    enum Variant { Secondary, Primary, Urgent }

    property string label: ""
    property int    variant: PopoverButton.Secondary
    property bool   enabled: true
    signal triggered()

    readonly property color _borderColor:
        variant === PopoverButton.Primary ? Theme.accent
      : variant === PopoverButton.Urgent  ? Theme.urgent
      :                                     Theme.fgDim
    readonly property color _textColor:
        variant === PopoverButton.Primary ? Theme.accent
      : variant === PopoverButton.Urgent  ? Theme.urgent
      :                                     Theme.fg
    readonly property color _tintColor:
        variant === PopoverButton.Primary ? Theme.accent
      : variant === PopoverButton.Urgent  ? Theme.urgent
      :                                     Theme.fg

    height: Theme.popoverButtonHeight
    radius: Theme.radius
    opacity: enabled ? 1.0 : 0.4
    color: hover.containsMouse && enabled
           ? Qt.rgba(_tintColor.r, _tintColor.g, _tintColor.b, 0.18)
           : Qt.rgba(_tintColor.r, _tintColor.g, _tintColor.b, 0.08)
    border.color: _borderColor
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root._textColor
        font.family: Theme.sansFamily
        font.pixelSize: Theme.fontPx - 1
        font.bold: true
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.triggered()
    }
}
