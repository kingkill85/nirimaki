import QtQuick

// Single-line text input. Themed chrome, focus border, placeholder,
// optional leading icon. Emits `accepted(text)` on Return.
//
//   TextField {
//       width: parent.width
//       placeholder: "Network password"
//       echoMode:    TextInput.Password
//       onAccepted:  (t) => NetworkService.connect(ssid, t)
//   }
//
// Same chrome as Toggle / Dropdown so settings forms read as one
// family. `leadingIcon` (a Nerd-Font glyph string) shows on the left
// — useful for search fields or for marking what a field controls.
Rectangle {
    id: root

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias maximumLength: input.maximumLength
    property alias validator: input.validator
    property alias inputMethodHints: input.inputMethodHints
    property alias readOnly: input.readOnly
    property alias selectByMouse: input.selectByMouse
    // True while the inner input holds keyboard focus. TextField isn't a
    // FocusScope, so the outer Item's activeFocus doesn't track the inner
    // TextInput — expose it explicitly for consumers like SearchableDropdown
    // that want to react to focus (e.g. open a list on click).
    readonly property alias inputFocused: input.activeFocus

    property string placeholder: ""
    property string leadingIcon: ""

    signal accepted(string text)
    signal editingFinished()

    function focusInput() { input.forceActiveFocus(); }

    implicitWidth:  240
    implicitHeight: Theme.controlHeight

    radius: Theme.radius
    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
    border.color: input.activeFocus ? Theme.accent : Theme.fgDim
    border.width: input.activeFocus
                  ? Theme.controlFocusBorderWidth
                  : Theme.controlBorderWidth

    Behavior on border.color { ColorAnimation { duration: 120 } }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.controlPadX
        anchors.rightMargin: Theme.controlPadX
        spacing: 8

        Text {
            id: iconText
            visible: root.leadingIcon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.leadingIcon
            color: Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }

        TextInput {
            id: input
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
                   - (iconText.visible ? iconText.implicitWidth + parent.spacing : 0)
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            font.family: Theme.sansFamily
            font.pixelSize: Theme.fontPx
            clip: true
            selectByMouse: true
            activeFocusOnTab: true

            onAccepted: root.accepted(text)
            onEditingFinished: root.editingFinished()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                visible: input.text === "" && !input.activeFocus
                text: root.placeholder
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                opacity: 0.7
            }
        }
    }

    // Click anywhere → focus the input.
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.IBeamCursor
        onPressed: (mouse) => { root.focusInput(); mouse.accepted = false; }
    }
}
