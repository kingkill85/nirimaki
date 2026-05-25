import QtQuick

// Labeled switch row — title + optional description on the left, a
// pill switch on the right. Stateless: emits `toggled(bool checked)`
// when the user clicks; callers flip `checked` in response so the
// component composes cleanly with model-driven UI.
//
//   Toggle {
//       label:       "Wi-Fi"
//       description: "Connected to MyNetwork"
//       checked:     NetworkService.wifiEnabled
//       onToggled:   NetworkService.setWifiEnabled(checked)
//   }
//
// Used for adapter power (bluetooth/wifi), per-device toggles in the
// bluetooth panel, mute toggles, DnD / NightLight / StayAwake panel
// switches.
Rectangle {
    id: root

    property string label: ""
    property string description: ""
    property bool   checked: false

    signal toggled(bool checked)

    activeFocusOnTab: true
    Keys.onReturnPressed: root._emit()
    Keys.onEnterPressed:  root._emit()
    Keys.onSpacePressed:  root._emit()

    function _emit() { root.toggled(!root.checked); }

    implicitWidth:  240
    implicitHeight: Math.max(Theme.controlHeight + 16, content.implicitHeight + 16)
    radius: Theme.radius
    color: hover.containsMouse
           ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)
           : "transparent"

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.controlPadX
        anchors.rightMargin: Theme.controlPadX
        spacing: Theme.controlPadX

        Column {
            width: parent.width - track.width - parent.spacing
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: root.label
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
            }
            Text {
                visible: root.description !== ""
                text: root.description
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 3
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        // Switch track + knob — pill shape when Theme.radius > 0,
        // square when radius is 0 (Omarchy parity: shape follows theme).
        Rectangle {
            id: track
            width: Theme.toggleTrackWidth
            height: Theme.toggleTrackHeight
            radius: Theme.radius > 0 ? height / 2 : 0
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.accent
                                : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)
            border.color: root.checked ? Theme.accent : Theme.fgDim
            border.width: 1

            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                width: Theme.toggleKnobSize
                height: Theme.toggleKnobSize
                radius: Theme.radius > 0 ? height / 2 : 0
                color: root.checked ? Theme.bg : Theme.fg
                x: root.checked
                   ? track.width - width - Theme.toggleKnobInset
                   : Theme.toggleKnobInset
                y: Theme.toggleKnobInset

                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._emit()
    }
}
