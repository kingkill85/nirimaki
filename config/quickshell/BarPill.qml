import QtQuick
import Quickshell

// Uniform bar-widget chrome: rounded hover-tinted rect with a centered
// content Row. Every clickable topbar plugin (audio, network, calendar,
// updates, weather, system-stats, media, voxtype, screen-record) sits
// inside one of these so the behavior — hover tint, pointer cursor,
// click-to-trigger — is identical across the bar.
//
// Default-property children are laid out left-to-right inside the
// inner Row. Plugins typically drop in an icon + label Text pair:
//
//   BarPill {
//       id: pill
//       active: popover.popupOpen
//       onClicked: popover.toggle()
//
//       Text { text: "󰚰"; ... }
//       Text { text: count;  ... }
//   }
//
// `active` lets the host tint the pill when its associated popover
// is open. `onWheel` / `onRightClicked` are opt-in power gestures —
// audio uses both (scroll = volume, right-click = summon mixer panel);
// most plugins ignore them.
Item {
    id: root

    // Hot tint when the host's associated popover (or other state) is open.
    property bool active: false

    // Spacing between default-property children inside the inner Row.
    property int spacing: 6

    // Hover-delayed tooltip below the pill. Empty = no tooltip.
    // The tooltip uses PopupWindow so it can escape the bar's 32-px
    // vertical extent (an in-scene Rectangle would clip).
    property string tooltipText: ""

    // Fires for left clicks. Right clicks go to `rightClicked` instead.
    signal clicked()
    signal rightClicked()
    signal middleClicked()
    // Normalised wheel ticks — +1 = scroll up, -1 = scroll down.
    signal wheel(int ticks)

    default property alias content: contentRow.children

    implicitHeight: Theme.barHeight
    implicitWidth:  rect.implicitWidth

    Rectangle {
        id: rect
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        implicitWidth: contentRow.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color: (hover.containsMouse || root.active) ? Theme.hot : "transparent"

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: root.spacing
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            onClicked: (mouse) => {
                tipTimer.stop();
                tip.visible = false;
                if      (mouse.button === Qt.RightButton)  root.rightClicked();
                else if (mouse.button === Qt.MiddleButton) root.middleClicked();
                else                                       root.clicked();
            }
            onWheel: (w) => {
                root.wheel(w.angleDelta.y > 0 ? 1 : -1);
                w.accepted = true;
            }
            onContainsMouseChanged: {
                if (root.tooltipText === "") return;
                if (containsMouse) tipTimer.restart();
                else               { tipTimer.stop(); tip.visible = false; }
            }
        }
    }

    Timer {
        id: tipTimer
        interval: Theme.tooltipDelay
        onTriggered: if (hover.containsMouse && root.tooltipText !== "") tip.visible = true
    }

    PopupWindow {
        id: tip
        visible: false
        color: "transparent"
        anchor.window: rect.QsWindow.window
        anchor.rect.x: rect.mapToItem(rect.QsWindow.window.contentItem, 0, 0).x
                       + (rect.width - implicitWidth) / 2
        anchor.rect.y: rect.QsWindow.window ? rect.QsWindow.window.height + 2 : 0
        implicitWidth:  tipLabel.implicitWidth + 2 * Theme.tooltipPadX
        implicitHeight: tipLabel.implicitHeight + 2 * Theme.tooltipPadY

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: 1
            radius: Theme.radius

            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: root.tooltipText
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.tooltipFontPx
            }
        }
    }
}
