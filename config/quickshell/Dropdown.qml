import QtQuick
import Quickshell

// Single-select dropdown. Header looks like a TextField; clicking
// opens a list of rows in a PopupWindow anchored to the header so the
// list escapes any clipping (Flickable, Column) and z-order siblings
// in the parent surface.
//
//   Dropdown {
//       model:   AudioService.sinks
//       textRole: "description"   // property on each model item to display
//       valueRole: "id"            // property to read back via currentValue
//       currentIndex: AudioService.defaultSinkIndex
//       onSelected:  (index, item) => AudioService.setDefaultSink(item.id)
//   }
//
// Model can be a plain JS array (`[{id, description, ...}, ...]`) or a
// Quickshell list model. `textRole` / `valueRole` are property names
// read from each item; pass `""` to use the item itself (strings).
//
// `placeholder` shows when no row is selected (currentIndex === -1).
Item {
    id: root

    property var    model: []
    property string textRole: ""
    property string valueRole: ""
    property int    currentIndex: -1
    property string placeholder: ""

    readonly property var currentItem: _itemAt(currentIndex)
    readonly property string currentText: _textOf(currentItem)
    readonly property var currentValue: _valueOf(currentItem)

    property bool _open: false

    signal selected(int index, var item)

    function _length() {
        if (!model) return 0;
        if (typeof model.length === "number") return model.length;
        if (typeof model.count  === "number") return model.count;
        return 0;
    }
    function _itemAt(i) {
        if (!model || i < 0 || i >= _length()) return null;
        if (typeof model.get === "function") return model.get(i);
        return model[i];
    }
    function _textOf(item) {
        if (item === null || item === undefined) return "";
        if (root.textRole === "") return String(item);
        return String(item[root.textRole] !== undefined ? item[root.textRole] : "");
    }
    function _valueOf(item) {
        if (item === null || item === undefined) return null;
        if (root.valueRole === "") return item;
        return item[root.valueRole];
    }

    readonly property real _listHeight:
        Math.min(Theme.dropdownMaxRows, root._length()) * Theme.dropdownRowHeight
        + 2 * Theme.controlBorderWidth

    function open() {
        // Compute popup placement in the containing window's coordinates.
        // mapToItem isn't binding-reactive so we recompute on every open;
        // the existing BarPopover follows the same pattern.
        const win = root.QsWindow ? root.QsWindow.window : null;
        if (!win || !win.contentItem) return;
        const p = root.mapToItem(win.contentItem, 0, 0);
        const need = _listHeight + 8;
        const flipUp = (p.y + root.height + need > win.height);
        listWin.anchor.rect.x = p.x;
        listWin.anchor.rect.y = flipUp ? (p.y - _listHeight - 4)
                                       : (p.y + root.height + 4);
        root._open = true;
    }
    function close() { root._open = false; }
    function toggle() {
        if (root._open) root.close();
        else            root.open();
    }
    function select(i) {
        root.currentIndex = i;
        root.selected(i, _itemAt(i));
        root.close();
    }

    implicitWidth:  240
    implicitHeight: Theme.controlHeight

    // ----- Header (the trigger) -----
    Rectangle {
        id: header
        anchors.fill: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
        border.color: root._open || hover.containsMouse ? Theme.accent : Theme.fgDim
        border.width: root._open
                      ? Theme.controlFocusBorderWidth
                      : Theme.controlBorderWidth

        Behavior on border.color { ColorAnimation { duration: 120 } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.controlPadX
            anchors.rightMargin: Theme.controlPadX
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - chev.implicitWidth - parent.spacing
                text: root.currentIndex >= 0 ? root.currentText : root.placeholder
                color: root.currentIndex >= 0 ? Theme.fg : Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                opacity: root.currentIndex >= 0 ? 1.0 : 0.7
                elide: Text.ElideRight
            }
            Text {
                id: chev
                anchors.verticalCenter: parent.verticalCenter
                text: root._open ? "󰅃" : "󰅀"   // chevron_up / chevron_down
                color: Theme.fgDim
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }

    // ----- Drop list (separate Wayland surface) -----
    PopupWindow {
        id: listWin
        visible: root._open
        color: "transparent"
        anchor.window: root.QsWindow ? root.QsWindow.window : null
        anchor.rect.width:  1
        anchor.rect.height: 1
        implicitWidth:  root.width
        implicitHeight: root._listHeight

        onVisibleChanged: {
            // Compositor-driven dismiss (xdg_popup grab + outside click)
            // flips visible to false. Sync _open back so we don't try to
            // keep it open.
            if (!visible && root._open) root._open = false;
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: Theme.cardBorderWidth
            radius: Theme.radius

            ListView {
                anchors.fill: parent
                anchors.margins: Theme.controlBorderWidth
                model: root.model
                clip: true
                interactive: count > Theme.dropdownMaxRows
                currentIndex: root.currentIndex

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Theme.dropdownRowHeight
                    color: rowHover.containsMouse
                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                           : (index === root.currentIndex
                              ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                              : "transparent")

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.controlPadX
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.controlPadX
                        text: root._textOf(parent.modelData !== undefined
                                           ? parent.modelData : root._itemAt(parent.index))
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(parent.index)
                    }
                }
            }
        }
    }
}
