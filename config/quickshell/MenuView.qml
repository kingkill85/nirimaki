import QtQuick
import QtQuick.Controls
import qs

// Reusable drilldown menu primitive — extracted from SettingsMenu so any
// plugin can have a search-and-drill menu without reimplementing the
// filter, keyboard nav, ListView delegate, breadcrumb, visibleWhen
// evaluation, etc.
//
// Data in, signals out:
//
//   MenuView {
//       tree:            myTreeData         // {nodeId: {icon, label/labelKey,
//                                            //          children?, action?, visibleWhen?}}
//       installedState:  myInstalledMap     // {feature: bool} for visibleWhen
//       placeholder:     "Settings"         // header text at root + breadcrumb prefix
//       onActionRequested: (a) => myDispatch(a)
//       onCloseRequested:  () => myCloseMenu()
//   }
//
// MenuView never dispatches actions itself; the consumer decides how
// `action` objects are interpreted. Same for closing — `closeRequested`
// fires when the user navigates up past the root (Esc / Left / Backspace
// at the root level).
Item {
    id: menu

    // ---- API ----
    // Menu tree. Each entry is a node keyed by id. Nodes are either
    // branches (have `children: [ids...]`) or leaves (have `action`).
    // Optional fields: `icon`, `label` (literal), `labelKey` (i18n),
    // `visibleWhen: { feature, is: "installed"|"missing" }`.
    property var tree: ({})
    // Optional feature/state map for visibleWhen evaluation. Keys are
    // feature names; values are booleans (true = installed). Missing
    // key → treated as "not installed".
    property var installedState: ({})
    // Header text at root level (e.g. "Settings", "Plugins"). Also the
    // first crumb in the breadcrumb when drilled-in.
    property string placeholder: ""

    signal actionRequested(var action)
    signal closeRequested

    // ---- Navigation state ----
    property var path: []             // drilldown stack of node ids
    property string filterText: ""
    property int selectedIndex: 0

    // ---- Theme tokens (re-exposed locally so the delegate sees them
    // by direct id lookup; avoids `Theme.X` references on every line). ----
    readonly property color accent:        Theme.accent
    readonly property color foreground:    Theme.fg
    readonly property color foregroundDim: Theme.fgDim
    readonly property int   cornerRadius:  Theme.radius
    readonly property string fontFamily:   Theme.monoFamily
    readonly property int contentMargin:   Theme.menuMargin
    readonly property int headerHeight:    Theme.menuHeaderHeight
    readonly property int contentSpacing:  Theme.menuSpacing
    readonly property int rowSpacing:      Theme.menuRowSpacing
    readonly property int rowHeight:       Theme.menuRowHeight

    // ---- Public methods ----
    function reset() {
        path = [];
        filterText = "";
        selectedIndex = 0;
        rebuild();
    }
    function focusMenu() { keyCatcher.forceActiveFocus(); }

    // ---- Helpers ----
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function _label(id) {
        const n = tree[id];
        if (!n) return id;
        if (n.labelKey) return I18n.t(n.labelKey);
        if (n.label)    return n.label;
        return id;
    }

    function _breadcrumb() {
        const parts = [placeholder];
        for (let i = 0; i < path.length; i++) parts.push(_label(path[i]));
        return parts.join(" › ");
    }

    function _currentNode() {
        return tree[path.length > 0 ? path[path.length - 1] : ""];
    }

    // True if a node should render. Branches: visible if any descendant
    // is visible. Leaves: gated by `visibleWhen.feature` looked up in
    // `installedState`.
    function _isNodeVisible(id) {
        const n = tree[id];
        if (!n) return false;
        if (n.children) {
            for (let i = 0; i < n.children.length; i++)
                if (_isNodeVisible(n.children[i])) return true;
            return false;
        }
        const v = n.visibleWhen;
        if (!v || !v.feature) return true;
        const state = installedState[v.feature];
        if (v.is === "installed") return state === true;
        if (v.is === "missing")   return state === false || state === undefined;
        return true;
    }

    function _enterChild(childId) {
        path = path.concat([childId]);
        filterText = "";
        selectedIndex = 0;
        rebuild();
    }

    // Navigate up. At root, emit closeRequested instead.
    function _pop() {
        if (path.length === 0) { menu.closeRequested(); return; }
        path = path.slice(0, path.length - 1);
        filterText = "";
        selectedIndex = 0;
        rebuild();
    }

    function rebuild() {
        displayModel.clear();
        const node = _currentNode();
        const kids = (node && node.children) ? node.children : [];
        const q = filterText.trim().toLowerCase();
        for (let i = 0; i < kids.length; i++) {
            const id = kids[i];
            const n = tree[id];
            if (!n) continue;
            if (!_isNodeVisible(id)) continue;
            const label = _label(id);
            if (q && label.toLowerCase().indexOf(q) < 0 &&
                    id.toLowerCase().indexOf(q) < 0) continue;
            displayModel.append({
                id: id,
                icon: n.icon || "",
                label: label,
                isBranch: !!n.children,
                index: displayModel.count
            });
        }
        if (displayModel.count === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
    }

    function select(delta) {
        if (displayModel.count === 0) return;
        selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        rebuild();
    }

    function activate(idx) {
        if (idx < 0 || idx >= displayModel.count) return;
        const item = displayModel.get(idx);
        const node = tree[item.id];
        if (!node) return;
        if (node.children) {
            _enterChild(item.id);
        } else if (node.action) {
            menu.actionRequested(node.action);
        }
    }

    // Data-driven rebuilds.
    onTreeChanged: rebuild()
    onInstalledStateChanged: rebuild()
    Component.onCompleted: rebuild()

    ListModel { id: displayModel }

    // ---- UI ----
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (menu.filterText) menu.setFilter("");
                else                 menu._pop();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace) {
                if (menu.filterText.length > 0)
                    menu.setFilter(menu.filterText.slice(0, -1));
                else
                    menu._pop();
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                menu.select(-1); event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                menu.select(1); event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                menu._pop(); event.accepted = true;
            } else if (event.key === Qt.Key_Right ||
                       event.key === Qt.Key_Return ||
                       event.key === Qt.Key_Enter) {
                menu.activate(menu.selectedIndex);
                event.accepted = true;
            } else if (event.text && event.text.length === 1 &&
                       event.text.charCodeAt(0) >= 32 &&
                       event.text.charCodeAt(0) !== 127) {
                menu.setFilter(menu.filterText + event.text);
                event.accepted = true;
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: menu.contentMargin
        spacing: menu.contentSpacing

        // Header — breadcrumb when not filtering, filter text otherwise.
        Item {
            width: parent.width
            height: menu.headerHeight

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: menu.filterText || menu._breadcrumb()
                color: menu.foreground
                opacity: menu.filterText ? 1 : 0.78
                font.family: menu.fontFamily
                font.pixelSize: Theme.menuFontPx
                elide: Text.ElideRight
            }
        }

        ListView {
            id: rowList
            width: parent.width
            height: parent.height - menu.headerHeight - menu.contentSpacing
            model: displayModel
            clip: true
            spacing: menu.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Keep the selected row in view when navigating with arrows.
            Connections {
                target: menu
                function onSelectedIndexChanged() {
                    if (menu.selectedIndex >= 0)
                        rowList.positionViewAtIndex(menu.selectedIndex, ListView.Contain);
                }
            }

            delegate: Rectangle {
                id: row
                required property int index
                required property string id
                required property string icon
                required property string label
                required property bool isBranch
                readonly property bool selected: index === menu.selectedIndex

                width: ListView.view.width
                height: menu.rowHeight
                radius: menu.cornerRadius
                color: row.selected
                       ? menu.withAlpha(menu.foreground, 0.08)
                       : menu.withAlpha(menu.foreground,
                                        mouseArea.containsMouse ? 0.045 : 0)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 14

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.icon
                        color: row.selected ? menu.accent : menu.foreground
                        font.family: menu.fontFamily
                        font.pixelSize: Theme.menuIconPx
                        width: 22
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - 14 - (row.isBranch ? 18 : 0)
                        text: row.label
                        color: row.selected ? menu.accent : menu.foreground
                        font.family: menu.fontFamily
                        font.pixelSize: Theme.menuFontPx
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: row.isBranch
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: row.selected ? menu.accent : menu.foregroundDim
                        font.family: menu.fontFamily
                        font.pixelSize: Theme.menuFontPx
                        width: 18
                        horizontalAlignment: Text.AlignRight
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        menu.selectedIndex = index;
                        menu.activate(index);
                    }
                }
            }
        }
    }
}
