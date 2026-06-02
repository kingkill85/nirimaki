import QtQuick
import qs

// Labeled single-line field for the Stream Deck key editor.
//
// `value` is driven from the deck model (a binding in the parent). We
// copy it into the TextField imperatively on change rather than binding
// `text: value` directly — a direct binding would be clobbered the
// moment the user types, so it would stop tracking later selections.
// Edits flow back out via `committed(text)` on Return or focus loss.
Column {
    id: root

    property string label: ""
    property string value: ""

    signal committed(string text)

    spacing: 4
    width: parent ? parent.width : 240

    onValueChanged: if (field.text !== value) field.text = value

    Text {
        text: root.label
        color: Theme.fgDim
        font.family: Theme.sansFamily
        font.pixelSize: Theme.fontPx - 1
    }
    TextField {
        id: field
        width: parent.width
        Component.onCompleted: text = root.value
        onAccepted: (t) => root.committed(t)
        onEditingFinished: root.committed(field.text)
    }
}
