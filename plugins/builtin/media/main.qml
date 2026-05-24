import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs

// Port of Omarchy's media.qml — MPRIS-driven now-playing widget.
//   Left click   → toggle play/pause
//   Middle click → next track
//   Right click  → toggle popup with album art + transport
//   Wheel up     → previous
//   Wheel down   → next
// Hidden when no player has a track.
Item {
    id: root

    property var barWindow: null

    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var activePlayer: {
        let playing = null;
        for (const p of players) {
            if (!p) continue;
            if (p.isPlaying) return p;
            if (!playing && p.trackTitle) playing = p;
        }
        return playing;
    }
    readonly property bool hasMedia:
        activePlayer !== null
        && (activePlayer.trackTitle || activePlayer.trackArtist)
    readonly property string playIcon:
        activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
    readonly property string title:
        activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string artist:
        activePlayer ? (activePlayer.trackArtist || "") : ""

    property bool popupOpen: false
    property real maxLabelWidth: 180

    visible: hasMedia
    implicitWidth:  hasMedia ? pill.width : 0
    implicitHeight: Theme.barHeight

    // Bar pill — only the play/pause glyph; the scrolling title was
    // distracting. Track title / artist still live on right-click popup.
    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width: 2 * Theme.padX + glyph.implicitWidth
        radius: Theme.radius
        color: (hoverArea.containsMouse || root.popupOpen) ? Theme.hot : "transparent"

        Text {
            id: glyph
            anchors.centerIn: parent
            text: root.playIcon
            color: root.activePlayer && root.activePlayer.isPlaying
                   ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (!root.activePlayer) return;
            if (mouse.button === Qt.MiddleButton) {
                if (root.activePlayer.canGoNext) root.activePlayer.next();
            } else if (mouse.button === Qt.RightButton) {
                root.popupOpen = !root.popupOpen;
            } else {
                if (root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying();
            }
        }
        onWheel: (wheel) => {
            if (!root.activePlayer) return;
            if (wheel.angleDelta.y > 0 && root.activePlayer.canGoPrevious)
                root.activePlayer.previous();
            else if (wheel.angleDelta.y < 0 && root.activePlayer.canGoNext)
                root.activePlayer.next();
        }
    }

    // ---------------- Popup ----------------
    PopupWindow {
        id: popup
        visible: root.popupOpen
        // Transparent window; the bordered card is the inner Rectangle.
        color: "transparent"

        // Drop directly under the pill, horizontally centred. `popupX`
        // is recomputed on every show because `mapToItem` isn't
        // binding-reactive (see Calendar.qml).
        property real popupX: 0
        anchor.window: root.barWindow
        anchor.rect.x: popupX
        anchor.rect.y: root.barWindow ? root.barWindow.height : 0

        onVisibleChanged: {
            if (visible) {
                popupX = pill.mapToItem(root.barWindow.contentItem, 0, 0).x
                       + (pill.width - implicitWidth) / 2;
                PopupBus.show(root);
                Qt.callLater(() => keyCatcher.forceActiveFocus());
            } else {
                PopupBus.hide(root);
                if (root.popupOpen) root.popupOpen = false;
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.popupOpen = false
        }

        implicitWidth:  340
        implicitHeight: contentColumn.implicitHeight + 24

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: Theme.cardBorderWidth
        }

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Art + text
            Row {
                spacing: 10
                width: parent.width

                Rectangle {
                    width: 64; height: 64; radius: Theme.radius
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
                    border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.2)
                    border.width: 1

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: root.activePlayer && root.activePlayer.trackArtUrl
                                ? root.activePlayer.trackArtUrl : ""
                        visible: source !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.activePlayer || !root.activePlayer.trackArtUrl
                        text: "󰝚"   // nf-md-music
                        color: Theme.fg
                        font.family: Theme.iconFamily
                        font.pixelSize: 28
                    }
                }

                Column {
                    spacing: 4
                    width: parent.width - 74

                    Text {
                        text: root.title || "Nothing playing"
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx + 1
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: root.artist
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                    }
                    Text {
                        text: root.activePlayer && root.activePlayer.trackAlbum
                              ? root.activePlayer.trackAlbum : ""
                        color: Theme.fgDim
                        opacity: 0.7
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                    }
                }
            }

            // Transport
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                TransportPill {
                    iconText: "󰒮"
                    canDo: root.activePlayer && root.activePlayer.canGoPrevious
                    onTriggered: if (root.activePlayer) root.activePlayer.previous()
                }
                TransportPill {
                    iconText: root.playIcon
                    iconSize: Theme.iconPx + 4
                    canDo: root.activePlayer && root.activePlayer.canTogglePlaying
                    onTriggered: if (root.activePlayer) root.activePlayer.togglePlaying()
                }
                TransportPill {
                    iconText: "󰒭"
                    canDo: root.activePlayer && root.activePlayer.canGoNext
                    onTriggered: if (root.activePlayer) root.activePlayer.next()
                }
            }
        }
    }

    // ---------------- TransportPill sub-component ----------------
    component TransportPill: Rectangle {
        id: pill

        property string iconText: ""
        property bool   canDo:    true
        property int    iconSize: Theme.iconPx
        signal triggered()

        width:  36
        height: 28
        radius: Theme.radius
        color:  pillHover.containsMouse && canDo ? Theme.hot : "transparent"
        opacity: canDo ? 1.0 : 0.4

        Text {
            anchors.centerIn: parent
            text: pill.iconText
            color: Theme.fg
            font.family: Theme.iconFamily
            font.pixelSize: pill.iconSize
        }

        MouseArea {
            id: pillHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pill.canDo ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (pill.canDo) pill.triggered()
        }
    }
}
