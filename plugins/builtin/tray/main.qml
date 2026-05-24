import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs

// StatusNotifierItem (SNI) tray host.
//   Left click   → activate()           (open / toggle the app's main UI)
//   Middle click → secondaryActivate()  (varies per app)
//   Right click  → opens the SNI menu via QsMenuAnchor anchored under the
//                  pill on the parent Bar window
//
// Ayatana indicators (e.g. Remmina) commonly stub activate() and only
// expose a menu — that's why right-click is the reliable interaction.
Row {
    id: root
    spacing: Theme.gap / 2

    // Bar.qml passes its PanelWindow in here — the menu anchor needs a
    // window to position its layer-shell popup against.
    property var barWindow: null

    Repeater {
        model: SystemTray.items

        delegate: Rectangle {
            id: cell
            required property var modelData

            implicitWidth:  Theme.barHeight - 2 * Theme.padY
            implicitHeight: Theme.barHeight - 2 * Theme.padY
            color: hover.containsMouse ? Theme.hot : "transparent"
            radius: Theme.radius

            // Letter placeholder visible while the icon hasn't resolved
            // (or for apps that don't ship one).
            Text {
                anchors.centerIn: parent
                visible: iconImage.status !== Image.Ready
                text: (cell.modelData.title || cell.modelData.id || "?")
                      .toString().charAt(0).toUpperCase()
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx - 1
                font.bold: true
            }

            Image {
                id: iconImage
                anchors.fill: parent
                anchors.margins: 3
                source: cell.modelData.icon || ""
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                cache: true
                sourceSize.width:  width
                sourceSize.height: height
            }

            // Declarative menu anchor. `anchor.item: cell` lets Quickshell
            // compute the window-space position automatically (otherwise
            // you'd have to map cell coords through the parent chain by
            // hand). Default edges = Top|Left → anchor at top-left of the
            // cell; we offset rect.y by cell.height so the menu opens just
            // BELOW the cell rather than covering the bar.
            QsMenuAnchor {
                id: menuAnchor
                menu: cell.modelData.menu
                anchor.item: cell
                anchor.rect.y: cell.height
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        // Many apps (Ayatana indicators like Remmina, lots
                        // of Electron apps) report hasMenu=true but stub
                        // activate(). Prefer the menu on left-click when
                        // one exists so the click always does something
                        // visible. Apps that really want left=activate
                        // typically still expose an "Open …" menu entry.
                        if (cell.modelData.hasMenu) menuAnchor.open();
                        else cell.modelData.activate();
                    } else if (mouse.button === Qt.MiddleButton) {
                        cell.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        if (cell.modelData.hasMenu) menuAnchor.open();
                    }
                }

                onWheel: (wheel) => {
                    cell.modelData.scroll(wheel.angleDelta.y, false);
                    wheel.accepted = true;
                }
            }
        }
    }
}
