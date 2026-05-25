import QtQuick
import qs

// Visual preview of every UI primitive in the kit. Lazy-summoned via
// the shell IPC; not part of any default bar layout.
//
//   quickshell ipc call shell summon dev-gallery
//   quickshell ipc call shell hide    dev-gallery
//
// Each section shows one primitive with a few configurations so the
// kit stays visually consistent as we add to it.
DialogShell {
    id: shell
    open: true
    cardWidth: 720
    cardHeight: 720
    dialogNamespace: "nirimaki-dev-gallery"

    onCloseRequested: Plugins.hide("dev-gallery")

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Plugins.hide("dev-gallery")

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 18
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content
                width: flick.width
                spacing: 24

                // ---- Header ----
                Row {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Nirimaki UI gallery"
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxLarge
                        font.bold: true
                    }
                    Item {
                        width: parent.width - 200
                        height: 1
                    }
                    Button {
                        label: "Close"
                        onTriggered: Plugins.hide("dev-gallery")
                    }
                }

                Section { title: "Toggle" }
                Toggle {
                    width: parent.width
                    label: "Wi-Fi"
                    description: "Connected to MyNetwork-5G"
                    checked: true
                    onToggled: checked = !checked
                }
                Toggle {
                    width: parent.width
                    label: "Do Not Disturb"
                    description: "Silence notifications"
                    checked: false
                    onToggled: checked = !checked
                }

                Section { title: "PanelSlider" }
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        text: "Volume"
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                    }
                    PanelSlider {
                        id: volSlider
                        width: parent.width
                        value: 0.65
                        onMoved:    (v) => value = v
                        onReleased: (v) => value = v
                    }

                    Text {
                        text: "Integer (0–100, step 5)"
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 2
                    }
                    PanelSlider {
                        width: parent.width
                        minimum: 0; maximum: 100; step: 5; integer: true
                        value: 30
                        onMoved:    (v) => value = v
                        onReleased: (v) => value = v
                    }
                }

                Section { title: "Dropdown" }
                Dropdown {
                    width: parent.width
                    placeholder: "Choose an output…"
                    textRole: "name"
                    valueRole: "id"
                    currentIndex: 1
                    model: [
                        { id: "spk", name: "Built-in speakers" },
                        { id: "hp",  name: "Audio jack — headphones" },
                        { id: "hdmi",name: "HDMI: Dell U2723QE" },
                        { id: "usb", name: "Pixel Buds 4 (Bluetooth)" }
                    ]
                    onSelected: (i, item) => console.log("dropdown picked", item.name)
                }

                Section { title: "SearchableDropdown" }
                SearchableDropdown {
                    width: parent.width
                    placeholder: "Search Wi-Fi networks…"
                    textRole: "ssid"
                    valueRole: "ssid"
                    model: [
                        { ssid: "MyNetwork-5G",  signal: 88, security: "WPA2" },
                        { ssid: "MyNetwork-2G",  signal: 71, security: "WPA2" },
                        { ssid: "Cafe-Guest",    signal: 56, security: "None" },
                        { ssid: "Neighbor-WIFI", signal: 34, security: "WPA3" },
                        { ssid: "Printer",       signal: 22, security: "None" }
                    ]
                    onSelected: (i, item) => console.log("ssid picked", item.ssid)
                }

                Section { title: "TextField + NumberField" }
                Row {
                    width: parent.width
                    spacing: 12
                    TextField {
                        width: (parent.width - 12) / 2
                        placeholder: "Wi-Fi password"
                        echoMode: TextInput.Password
                    }
                    NumberField {
                        width: (parent.width - 12) / 2
                        minimum: 0; maximum: 600; integer: true
                        value: 300
                        suffix: " s"
                    }
                }

                Section { title: "Button variants" }
                Row {
                    width: parent.width
                    spacing: 12
                    Button { label: "Cancel" }
                    Button { label: "Connect";   variant: Button.Primary }
                    Button { label: "Forget";    variant: Button.Urgent }
                    Button { label: "Disabled";  enabled: false }
                }

                Section { title: "Tooltip (hover the chip below)" }
                Rectangle {
                    id: tipTarget
                    width: 120
                    height: Theme.controlHeight
                    radius: Theme.radius
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
                    border.color: Theme.fgDim
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "hover me"
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx
                    }
                }
                Tooltip {
                    target: tipTarget
                    text: "I appear after 600 ms"
                    position: "right"
                }

                Section { title: "PopoverHeader + Divider + Actions" }
                Rectangle {
                    width: parent.width
                    height: hdrCol.implicitHeight + 24
                    color: Theme.cardBg
                    border.color: Theme.cardBorderColor
                    border.width: Theme.cardBorderWidth
                    radius: Theme.radius

                    Column {
                        id: hdrCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: Theme.popoverSpacing

                        PopoverHeader {
                            icon: "󰚰"
                            title: "Updates"
                            subtitle: "12 packages pending"
                        }
                        PopoverDivider {}
                        PopoverActions {
                            PopoverButton { label: "Defer" }
                            PopoverButton {
                                label: "Run update"
                                variant: PopoverButton.Primary
                            }
                        }
                    }
                }
            }
        }
    }

    component Section: Text {
        property string title: ""
        text: title
        color: Theme.fgDim
        font.family: Theme.sansFamily
        font.pixelSize: Theme.fontPx - 1
        font.bold: true
        font.letterSpacing: 1
    }
}
