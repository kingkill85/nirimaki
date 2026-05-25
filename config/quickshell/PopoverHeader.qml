import QtQuick

// Big-icon header row for the top of every BarPopover. Keeps icon size,
// title typography, and subtitle styling consistent across the bar.
//
//   PopoverHeader {
//       icon:     "󰚰"
//       title:    I18n.t("updates.title")
//       subtitle: count + " " + I18n.t("updates.many")
//   }
//
// `iconColor` defaults to Theme.fg but plugins override it to reflect
// state (e.g. Theme.fgDim when bluetooth is off, Theme.urgent for an
// alert). `subtitle` is hidden when empty so simple headers stay tidy.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color  iconColor: Theme.fg

    implicitHeight: row.implicitHeight
    width: parent ? parent.width : 0

    Row {
        id: row
        width: parent.width
        spacing: 10

        Text {
            id: iconText
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.iconColor
            font.family: Theme.iconFamily
            font.pixelSize: Theme.popoverHeaderIconPx
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: parent.width
                   - (iconText.visible ? iconText.implicitWidth + row.spacing : 0)

            Text {
                text: root.title
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
            }
            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 3
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
