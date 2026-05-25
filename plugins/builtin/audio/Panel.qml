import QtQuick
import qs

// Full audio mixer — lazy-summoned overlay.
//
//   quickshell ipc call shell summon audio
//
// Three tabs:
//   1. OUTPUT   default-sink picker + master slider + mute
//   2. INPUT    default-source picker + master slider + mute
//   3. APPS     per-app playback streams (one row each)
//
// Picking a device from a tab's dropdown sets it as the persisted
// Pipewire default — wireplumber writes it to user metadata so the
// choice survives reboot.
DialogShell {
    id: shell
    open: true
    cardWidth: 540
    cardHeight: 520
    dialogNamespace: "nirimaki-audio-panel"

    onCloseRequested: Plugins.hide("audio")

    property int currentTab: 0   // 0 = output, 1 = input, 2 = apps

    Item {
        width: 0; height: 0
        focus: true
        Keys.onEscapePressed: Plugins.hide("audio")
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18

        // ---- Header ----
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12
            height: 40

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰕾"
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.fontPxLarge + 4
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: parent.width - 80 - parent.spacing * 2 - 28

                Text {
                    text: I18n.t("audio.mixer")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                }
                Text {
                    text: I18n.t("audio.summary")
                          .replace("{0}", AudioService.sinks.length)
                          .replace("{1}", AudioService.sources.length)
                          .replace("{2}", AudioService.sinkStreams.length)
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                }
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.t("audio.close")
                onTriggered: Plugins.hide("audio")
            }
        }

        // ---- Tab bar ----
        TabBar {
            id: tabs
            anchors.top: header.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            tabs: [
                I18n.t("audio.tab.output"),
                I18n.t("audio.tab.input"),
                I18n.t("audio.tab.apps")
            ]
            currentIndex: shell.currentTab
            onTabClicked: (i) => shell.currentTab = i
        }

        // ---- Tab content ----
        Item {
            anchors.top: tabs.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // ---------------- OUTPUT tab ----------------
            Column {
                visible: shell.currentTab === 0
                width: parent.width
                spacing: 12

                Text {
                    text: I18n.t("audio.section.default_output")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                Dropdown {
                    id: sinkPicker
                    width: parent.width
                    placeholder: I18n.t("audio.placeholder.output")
                    model: AudioService.sinks
                    textRole: "description"
                    currentIndex: _findCurrent()

                    function _findCurrent() {
                        const sinks = AudioService.sinks;
                        const cur = AudioService.defaultSink;
                        for (let i = 0; i < sinks.length; i++)
                            if (sinks[i] === cur) return i;
                        return -1;
                    }

                    Connections {
                        target: AudioService
                        function onDefaultSinkChanged() {
                            sinkPicker.currentIndex = sinkPicker._findCurrent();
                        }
                    }

                    onSelected: (idx, item) => AudioService.setDefaultSink(item)
                }

                Item { width: parent.width; height: 4 }

                Text {
                    text: I18n.t("audio.section.volume")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                Row {
                    width: parent.width
                    spacing: 12

                    PanelSlider {
                        width: parent.width - muteSinkBtn.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        value: AudioService.defaultSinkVolume
                        fillColor: AudioService.defaultSinkMuted ? Theme.fgDim : Theme.accent
                        onMoved:    (v) => AudioService.setVolume(AudioService.defaultSink, v)
                        onReleased: (v) => AudioService.setVolume(AudioService.defaultSink, v)
                    }
                    Button {
                        id: muteSinkBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: AudioService.defaultSinkMuted
                               ? I18n.t("audio.unmute") : I18n.t("audio.mute")
                        variant: AudioService.defaultSinkMuted ? Button.Urgent : Button.Secondary
                        onTriggered: AudioService.toggleMute(AudioService.defaultSink)
                    }
                }

                Text {
                    text: AudioService.defaultSinkMuted
                        ? I18n.t("audio.muted")
                        : Math.round(AudioService.defaultSinkVolume * 100) + "%"
                    color: Theme.fgDim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontPx - 2
                }
            }

            // ---------------- INPUT tab ----------------
            Column {
                visible: shell.currentTab === 1
                width: parent.width
                spacing: 12

                Text {
                    text: I18n.t("audio.section.default_input")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                Dropdown {
                    id: sourcePicker
                    visible: AudioService.sources.length > 0
                    width: parent.width
                    placeholder: I18n.t("audio.placeholder.input")
                    model: AudioService.sources
                    textRole: "description"
                    currentIndex: _findCurrent()

                    function _findCurrent() {
                        const sources = AudioService.sources;
                        const cur = AudioService.defaultSource;
                        for (let i = 0; i < sources.length; i++)
                            if (sources[i] === cur) return i;
                        return -1;
                    }

                    Connections {
                        target: AudioService
                        function onDefaultSourceChanged() {
                            sourcePicker.currentIndex = sourcePicker._findCurrent();
                        }
                    }

                    onSelected: (idx, item) => AudioService.setDefaultSource(item)
                }

                Item {
                    visible: AudioService.sources.length > 0
                    width: parent.width
                    height: 4
                }

                Text {
                    visible: AudioService.sources.length > 0
                    text: I18n.t("audio.section.level")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 2
                    font.bold: true
                    font.letterSpacing: 2
                }

                Row {
                    visible: AudioService.sources.length > 0
                    width: parent.width
                    spacing: 12

                    PanelSlider {
                        width: parent.width - muteSourceBtn.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        value: AudioService.defaultSourceVolume
                        fillColor: AudioService.defaultSourceMuted ? Theme.fgDim : Theme.accent
                        onMoved:    (v) => AudioService.setVolume(AudioService.defaultSource, v)
                        onReleased: (v) => AudioService.setVolume(AudioService.defaultSource, v)
                    }
                    Button {
                        id: muteSourceBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: AudioService.defaultSourceMuted
                               ? I18n.t("audio.unmute") : I18n.t("audio.mute")
                        variant: AudioService.defaultSourceMuted ? Button.Urgent : Button.Secondary
                        onTriggered: AudioService.toggleMute(AudioService.defaultSource)
                    }
                }

                Text {
                    visible: AudioService.sources.length > 0
                    text: AudioService.defaultSourceMuted
                        ? I18n.t("audio.muted")
                        : Math.round(AudioService.defaultSourceVolume * 100) + "%"
                    color: Theme.fgDim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontPx - 2
                }

                Text {
                    visible: AudioService.sources.length === 0
                    text: I18n.t("audio.no_inputs")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx - 1
                    font.italic: true
                }
            }

            // ---------------- APPS tab ----------------
            // One row per process. Browsers expose one PwNode per
            // tab/audio source plus a master node; the row aggregates
            // the whole group so the user sees "Zen — 5 streams" once
            // and the slider writes the new level to every constituent.
            // Click the chevron to expand and see / mute individual
            // streams.
            Flickable {
                id: appsFlick
                visible: shell.currentTab === 2
                anchors.fill: parent
                contentWidth: width
                contentHeight: appsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: appsCol
                    width: appsFlick.width
                    spacing: 10

                    Repeater {
                        model: AudioService.sinkStreamGroups

                        delegate: Rectangle {
                            id: groupRow
                            required property var modelData
                            readonly property var group: groupRow.modelData
                            readonly property int streamCount: group ? group.streams.length : 0
                            readonly property real groupVolume: AudioService.groupVolume(group)
                            readonly property bool groupMuted:  AudioService.groupMuted(group)
                            property bool expanded: false

                            width: parent.width
                            height: groupCol.implicitHeight + 16
                            radius: Theme.radius
                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)

                            Column {
                                id: groupCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                // Header: icon · app name (+ "× N") · % · chevron
                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: groupRow.group ? groupRow.group.icon : ""
                                        color: Theme.fg
                                        font.family: Theme.iconFamily
                                        font.pixelSize: Theme.iconPx
                                    }
                                    Text {
                                        id: appLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 100 - chevronText.implicitWidth - 3 * parent.spacing
                                        text: groupRow.streamCount > 1
                                              ? (groupRow.group.appName + "  × " + groupRow.streamCount)
                                              : (groupRow.group ? AudioService.streamLabel(groupRow.group.streams[0]) : "")
                                        color: Theme.fg
                                        font.family: Theme.sansFamily
                                        font.pixelSize: Theme.fontPx
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: groupRow.groupMuted
                                            ? I18n.t("audio.muted")
                                            : Math.round(groupRow.groupVolume * 100) + "%"
                                        color: Theme.fgDim
                                        font.family: Theme.monoFamily
                                        font.pixelSize: Theme.fontPx - 2
                                    }
                                    Text {
                                        id: chevronText
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: groupRow.streamCount > 1
                                        text: groupRow.expanded ? "󰅃" : "󰅀"
                                        color: Theme.fgDim
                                        font.family: Theme.iconFamily
                                        font.pixelSize: Theme.iconPx
                                    }
                                }

                                // Master volume row (operates on the whole group).
                                Row {
                                    width: parent.width
                                    spacing: 8

                                    PanelSlider {
                                        width: parent.width - groupMute.width - parent.spacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: groupRow.groupVolume
                                        onMoved:    (v) => AudioService.setGroupVolume(groupRow.group, v)
                                        onReleased: (v) => AudioService.setGroupVolume(groupRow.group, v)
                                    }
                                    Button {
                                        id: groupMute
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: groupRow.groupMuted
                                               ? I18n.t("audio.unmute") : I18n.t("audio.mute")
                                        variant: groupRow.groupMuted
                                                 ? Button.Urgent : Button.Secondary
                                        onTriggered: AudioService.toggleGroupMute(groupRow.group)
                                    }
                                }

                                // Expanded sub-list — one bullet per stream
                                // in the group, with the media.name visible
                                // and a per-stream mute toggle.
                                Column {
                                    visible: groupRow.expanded && groupRow.streamCount > 1
                                    width: parent.width
                                    spacing: 2

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Theme.fgDim
                                        opacity: 0.18
                                    }

                                    Repeater {
                                        model: groupRow.group ? groupRow.group.streams : []

                                        delegate: Row {
                                            required property var modelData
                                            readonly property var sub: modelData
                                            readonly property bool subMuted:
                                                sub && sub.audio ? sub.audio.muted : false

                                            width: parent.width
                                            height: 24
                                            spacing: 6

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "·"
                                                color: Theme.fgDim
                                                font.family: Theme.sansFamily
                                                font.pixelSize: Theme.fontPx
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 100
                                                text: {
                                                    const p = parent.sub && parent.sub.properties
                                                            ? parent.sub.properties : {};
                                                    return String(p["media.name"]
                                                               || AudioService.displayName(parent.sub));
                                                }
                                                color: parent.subMuted ? Theme.fgDim : Theme.fg
                                                font.family: Theme.sansFamily
                                                font.pixelSize: Theme.fontPx - 2
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 60
                                                height: 22
                                                radius: Theme.radius
                                                color: subMuteHover.containsMouse
                                                       ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)
                                                       : "transparent"
                                                border.color: parent.subMuted ? Theme.urgent : Theme.fgDim
                                                border.width: 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: parent.parent.subMuted
                                                        ? I18n.t("audio.unmute") : I18n.t("audio.mute")
                                                    color: parent.parent.subMuted ? Theme.urgent : Theme.fg
                                                    font.family: Theme.sansFamily
                                                    font.pixelSize: Theme.fontPx - 3
                                                }

                                                MouseArea {
                                                    id: subMuteHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: AudioService.toggleMute(parent.parent.sub)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Whole-row click toggles expansion (when there
                            // are sub-streams). MouseArea sits BEHIND the
                            // slider / mute button so clicks on those still
                            // reach the children.
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                cursorShape: groupRow.streamCount > 1
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (groupRow.streamCount > 1)
                                        groupRow.expanded = !groupRow.expanded;
                                }
                            }
                        }
                    }

                    Text {
                        visible: AudioService.sinkStreamGroups.length === 0
                        text: I18n.t("audio.no_apps")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx - 1
                        font.italic: true
                    }
                }
            }
        }
    }
}
