import QtQuick
import QtQuick.Controls
import Quickshell

// One LockSurface per output. Renders the current wallpaper (same
// image swaybg displays on the unlocked session) with a dim scrim,
// then a clock + date at top and a centred password card in the
// middle. Palette and translations are read from the symlinked
// Theme + I18n singletons (lock runs as a separate quickshell
// process; both .qml files are symlinked from ../).
Rectangle {
    id: root
    required property var context

    // Solid fallback — shows through if the wallpaper Image fails to
    // load (broken symlink, etc.).
    color: Theme.bg

    // ---- Wallpaper backdrop ----
    // Points at ~/.config/theme/current/wallpaper (set by the
    // background picker) so the lock screen matches the active
    // desktop wallpaper. If that symlink doesn't exist the Image
    // silently fails and Theme.bg shows.
    Image {
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.config/theme/current/wallpaper"
        fillMode: Image.PreserveAspectCrop
        cache: true
        asynchronous: true
    }
    // Dim scrim so the white-on-wallpaper clock + password card stay
    // legible against bright images.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    // ---- Clock + date stack (top centre) ----
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.18
        spacing: 8

        property date now: new Date()

        Timer {
            id: clockTimer
            running: true
            repeat: true
            interval: 1000
            onTriggered: parent.now = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale().toString(parent.now, "HH:mm")
            color: Theme.fg
            font.family: Theme.monoFamily
            font.pixelSize: 96
            font.bold: true
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale().toString(parent.now, "dddd, d. MMMM yyyy")
            color: Theme.fgDim
            font.family: Theme.sansFamily
            font.pixelSize: 18
        }
    }

    // ---- Password card (centre, slightly below middle) ----
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: parent.height * 0.05
        width: 520
        height: cardCol.implicitHeight + 32
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.fg
        border.width: 2

        Column {
            id: cardCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            TextField {
                id: passwordBox
                width: parent.width
                padding: 14
                focus: true
                enabled: !root.context.unlockInProgress
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                placeholderText: I18n.t("lock.password")
                // Centre the placeholder + typed bullets so the
                // placeholder doesn't cling to the left edge of the
                // card; same alignment for the actual entry.
                horizontalAlignment: TextInput.AlignHCenter

                font.family: Theme.monoFamily
                font.pixelSize: 20
                // Space the typed bullets out so they read as
                // separate dots instead of one fat line.
                font.letterSpacing: 4
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                selectionColor: Theme.fg
                selectedTextColor: Theme.bg

                // No own background — the outer card already provides
                // the border + fill. A transparent rectangle removes the
                // default Fusion-style frame that drew the inner border.
                background: Rectangle {
                    color: "transparent"
                    border.width: 0
                }

                onTextChanged: root.context.currentText = text
                onAccepted:    root.context.tryUnlock()

                // Keep all per-screen LockSurfaces in sync.
                Connections {
                    target: root.context
                    function onCurrentTextChanged() {
                        if (passwordBox.text !== root.context.currentText)
                            passwordBox.text = root.context.currentText;
                    }
                }
            }

            Text {
                visible: root.context.showFailure
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("lock.bad_password")
                color: Theme.urgent
                font.family: Theme.sansFamily
                font.pixelSize: 13
            }
        }
    }
}
