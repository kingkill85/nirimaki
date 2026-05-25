import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs

// Port of Omarchy's media.qml — MPRIS-driven now-playing widget.
//   Left click   → toggle popup with album art + transport
//   Middle click → toggle play/pause
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

    property real maxLabelWidth: 180

    visible: hasMedia
    implicitWidth:  hasMedia ? pill.implicitWidth : 0
    implicitHeight: Theme.barHeight

    // Bar pill — only the play/pause glyph; the scrolling title was
    // distracting. Track title / artist live on the popover.
    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked: if (root.activePlayer) popover.toggle()
        onMiddleClicked: {
            if (root.activePlayer && root.activePlayer.canTogglePlaying)
                root.activePlayer.togglePlaying();
        }
        onWheel: (ticks) => {
            if (!root.activePlayer) return;
            if (ticks > 0 && root.activePlayer.canGoPrevious)
                root.activePlayer.previous();
            else if (ticks < 0 && root.activePlayer.canGoNext)
                root.activePlayer.next();
        }

        Text {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            text: root.playIcon
            color: root.activePlayer && root.activePlayer.isPlaying
                   ? Theme.fg : Theme.fgDim
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }

    // ---------------- Popup ----------------
    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  340
        implicitHeight: contentColumn.implicitHeight + 2 * contentMargin

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            // Custom header: media uses album art (an Image) instead of
            // a font-glyph, so it can't use PopoverHeader. Typography
            // and spacing still mirror the standard header.
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
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 74

                    Text {
                        text: root.title || "Nothing playing"
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: root.artist
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 3
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

            PopoverDivider {}

            // Transport — three fixed-width icon buttons centered.
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
