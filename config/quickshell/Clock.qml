import QtQuick

Text {
    id: clock
    text: Qt.formatDateTime(new Date(), "ddd HH:mm")
    color: Theme.fg
    font.family: Theme.sansFamily
    font.pixelSize: Theme.fontPx
    verticalAlignment: Text.AlignVCenter

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd HH:mm")
    }
}
