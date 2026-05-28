import QtQuick

// Generic action button — same shape and variants as PopoverButton,
// but sized for panels / dialogs / settings forms (controlHeight by
// default, not popoverButtonHeight). Use this anywhere outside a
// popover action row.
//
//   Button {
//       label:   "Connect"
//       variant: Button.Primary
//       onTriggered: NetworkService.activate(ssid)
//   }
//
// Variants:
//   - Primary   — accent border + accent text; the popover/panel's main affordance
//   - Secondary — fgDim border + fg text; neutral toggles, dismiss
//   - Urgent    — urgent border + urgent text; destructive (forget, disconnect)
//
// `enabled: false` dims to 0.4 opacity and disables the click.
Rectangle {
    id: root

    enum Variant { Secondary, Primary, Urgent }

    property string label: ""
    property int    variant: Button.Secondary
    property bool   enabled: true
    property int    iconLeading: 0   // optional Nerd-Font glyph code point — leave 0 for none

    signal triggered()

    readonly property color _borderColor:
        variant === Button.Primary ? Theme.accent
      : variant === Button.Urgent  ? Theme.urgent
      :                              Theme.fgDim
    readonly property color _textColor:
        variant === Button.Primary ? Theme.accent
      : variant === Button.Urgent  ? Theme.urgent
      :                              Theme.fg
    readonly property color _tintColor:
        variant === Button.Primary ? Theme.accent
      : variant === Button.Urgent  ? Theme.urgent
      :                              Theme.fg

    // Icon-only mode (label === "" + iconLeading set) collapses the
    // button to a square ~controlHeight, otherwise the standard 80-min
    // width keeps text buttons readable.
    readonly property bool _iconOnly: label === "" && iconLeading !== 0

    implicitWidth: _iconOnly
                     ? Theme.controlHeight
                     : Math.max(80, _labelText.implicitWidth + 2 * Theme.controlPadX)
    height: Theme.controlHeight
    radius: Theme.radius
    opacity: enabled ? 1.0 : 0.4
    color: hover.containsMouse && enabled
           ? Qt.rgba(_tintColor.r, _tintColor.g, _tintColor.b, 0.18)
           : Qt.rgba(_tintColor.r, _tintColor.g, _tintColor.b, 0.08)
    border.color: _borderColor
    border.width: Theme.controlBorderWidth

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
        anchors.centerIn: parent
        spacing: 6

        // Nerd-Font glyph rendered in iconFamily. Hidden when iconLeading
        // is 0 (default). Sized 2px above fontPx so the glyph optically
        // matches the bold label text next to it.
        Text {
            visible: root.iconLeading !== 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconLeading !== 0 ? String.fromCodePoint(root.iconLeading) : ""
            color: root._textColor
            font.family: Theme.iconFamily
            font.pixelSize: Theme.fontPx + 2
        }
        Text {
            id: _labelText
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root._textColor
            font.family: Theme.sansFamily
            font.pixelSize: Theme.fontPx
            font.bold: true
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.triggered()
    }
}
