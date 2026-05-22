import QtQuick
import QtQuick.Controls

// Nirimaki SDDM greeter — visually mirrors config/quickshell/lock/
// LockSurface.qml so the login screen and lock screen are the same
// experience. Reads wallpaper + palette from `state/` (set up by
// install/login/sddm.sh, refreshed by `nirimaki-sddm-sync` on every
// theme switch). All paths in the QML are relative — SDDM resolves
// them from the theme directory at /usr/share/sddm/themes/nirimaki/.
Rectangle {
    id: root
    color: "#000000"

    // ---- Palette ---------------------------------------------------
    // Defaults match Theme.qml so the screen still renders if the
    // state file is missing.
    property color bg:     "#101315"
    property color fg:     "#cacccc"
    property color accent: "#cacccc"
    property color urgent: "#a55555"
    readonly property color fgDim: Qt.darker(fg, 1.65)

    // ---- SDDM state ------------------------------------------------
    property string currentUser: userModel.lastUser
    property bool   loginFailed: false
    property int    sessionIndex: sessionModel.lastIndex

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loginFailed = true
            passwordBox.text = ""
            passwordBox.forceActiveFocus()
        }
        function onLoginSucceeded() { root.loginFailed = false }
    }

    // ---- Load palette from state/colors.json -----------------------
    // XMLHttpRequest is the only file-reader available to plain QML in
    // the greeter — no QtIo or Quickshell. JSON keeps parsing trivial.
    Component.onCompleted: {
        try {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", "state/colors.json", false)
            xhr.send()
            if (xhr.status === 0 || xhr.status === 200) {
                const p = JSON.parse(xhr.responseText)
                if (p.bg)     root.bg     = p.bg
                if (p.fg)     root.fg     = p.fg
                if (p.accent) root.accent = p.accent
                if (p.urgent) root.urgent = p.urgent
            }
        } catch (e) { /* keep defaults */ }
        passwordBox.forceActiveFocus()
    }

    // ---- Wallpaper backdrop ----------------------------------------
    Image {
        anchors.fill: parent
        source: "state/wallpaper"
        fillMode: Image.PreserveAspectCrop
        cache: true
        asynchronous: true
    }
    // Dim scrim so white-on-wallpaper text stays legible against
    // bright images — matches LockSurface's 0.55 alpha.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    // ---- Clock + date stack ----------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.18
        spacing: 8

        property date now: new Date()

        Timer {
            running: true
            repeat: true
            interval: 1000
            onTriggered: parent.now = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale().toString(parent.now, "HH:mm")
            color: root.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 96
            font.bold: true
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale().toString(parent.now, "dddd, d. MMMM yyyy")
            color: root.fgDim
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
        }
    }

    // ---- Password card ---------------------------------------------
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter:   parent.verticalCenter
        anchors.verticalCenterOffset: parent.height * 0.05
        width: 520
        height: cardCol.implicitHeight + 32
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.97)
        border.color: root.fg
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
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                placeholderText: qsTr("Password")
                horizontalAlignment: TextInput.AlignHCenter

                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                font.letterSpacing: 4
                color: root.fg
                placeholderTextColor: root.fgDim
                selectionColor: root.fg
                selectedTextColor: root.bg

                background: Rectangle {
                    color: "transparent"
                    border.width: 0
                }

                onTextChanged: root.loginFailed = false
                Keys.onReturnPressed: sddm.login(root.currentUser, passwordBox.text, root.sessionIndex)
                Keys.onEnterPressed:  sddm.login(root.currentUser, passwordBox.text, root.sessionIndex)
            }

            Text {
                visible: root.loginFailed
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Wrong password")
                color: root.urgent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
            }
        }
    }
}
