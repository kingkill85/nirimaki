import QtQuick
import Quickshell

// Dropdown where the header doubles as a search input. The model is
// filtered live by the typed text matched against `textRole`.
//
// Same API as Dropdown but the trigger area is a TextField; the
// filtered list builds from `model` filtered by a case-insensitive
// substring match on `textRole`.
//
//   SearchableDropdown {
//       model:    NetworkService.savedConnections
//       textRole: "name"
//       placeholder: "Search saved networks…"
//       onSelected: (index, item) => NetworkService.activate(item)
//   }
Item {
    id: root

    property var    model: []
    property string textRole: ""
    property string valueRole: ""
    property int    currentIndex: -1
    property string placeholder: "Search…"

    readonly property var currentItem: _itemAt(currentIndex)
    readonly property string currentText: _textOf(currentItem)
    readonly property var currentValue: _valueOf(currentItem)

    property bool _open: false
    property string _query: ""

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
    function _filtered() {
        if (!model) return [];
        const q = _query.toLowerCase();
        const out = [];
        const n = _length();
        for (let i = 0; i < n; i++) {
            const it = _itemAt(i);
            const t = _textOf(it).toLowerCase();
            if (q === "" || t.indexOf(q) !== -1) {
                out.push({ index: i, item: it, text: _textOf(it) });
            }
        }
        return out;
    }

    readonly property real _listHeight:
        Math.min(Theme.dropdownMaxRows, _filtered().length) * Theme.dropdownRowHeight
        + 2 * Theme.controlBorderWidth

    function open()   {
        const win = root.QsWindow ? root.QsWindow.window : null;
        if (!win || !win.contentItem) return;
        const p = root.mapToItem(win.contentItem, 0, 0);
        const need = _listHeight + 8;
        const flipUp = (p.y + root.height + need > win.height);
        listWin.anchor.rect.x = p.x;
        listWin.anchor.rect.y = flipUp ? (p.y - _listHeight - 4) : (p.y + root.height + 4);
        root._open = true;
    }
    function close()  { root._open = false; }
    function select(i) {
        root.currentIndex = i;
        root.selected(i, _itemAt(i));
        root.close();
    }

    implicitWidth:  240
    implicitHeight: Theme.controlHeight

    TextField {
        id: search
        anchors.fill: parent
        placeholder: root.placeholder
        leadingIcon: ""    // nf-fa-search
        onTextChanged: {
            root._query = text;
            if (!root._open) root.open();
        }
        onAccepted: (t) => {
            const f = root._filtered();
            if (f.length > 0) root.select(f[0].index);
        }
    }

    PopupWindow {
        id: listWin
        visible: root._open && root._filtered().length > 0
        color: "transparent"
        anchor.window: root.QsWindow ? root.QsWindow.window : null
        anchor.rect.width:  1
        anchor.rect.height: 1
        implicitWidth:  root.width
        implicitHeight: root._listHeight

        onVisibleChanged: {
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
                model: root._filtered()
                clip: true

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.dropdownRowHeight
                    color: rowHover.containsMouse
                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                           : (modelData.index === root.currentIndex
                              ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                              : "transparent")

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.controlPadX
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.controlPadX
                        text: modelData.text
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
                        onClicked: root.select(modelData.index)
                    }
                }
            }
        }
    }
}
