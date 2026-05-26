import QtQuick
import qs

// Graphical monitor layout editor — lazy-summoned via
//   quickshell ipc call shell summon monitors
//
// Two sections, top→bottom:
//   1. Drag-arrange canvas. Each connected output is a draggable
//      rectangle scaled by its current mode size. Drop position is
//      written back into the working snapshot's position{X,Y}.
//   2. Per-output form. Output dropdown picks which monitor to edit;
//      mode + scale dropdowns mutate the working snapshot.
//
// Footer holds Apply / Revert. Apply writes monitors.kdl, niri's
// own file-watcher reloads, and a 10-second confirm-or-revert modal
// pops over the panel so a bad mode pick can't lock you out.
DialogShell {
    id: shell
    open: true
    cardWidth: 920
    cardHeight: 860
    dialogNamespace: "nirimaki-monitors"

    onCloseRequested: shell.requestClose()

    // ---- State ----
    // Mutable working copy of the monitor snapshot. Apply commits this
    // to monitors.kdl; cancel discards it by re-pulling from the
    // service.
    property var working: []
    property int selectedIndex: 0

    // Confirm-or-revert overlay state. countdown ticks down once a
    // monitors.kdl write has landed; on 0 we revert.
    property bool confirmOpen: false
    property int  countdown: 10

    function requestClose() {
        if (confirmOpen) return;   // can't dismiss mid-revert
        Plugins.hide("monitors");
    }

    function reloadFromService() {
        working = MonitorService.snapshot();
        if (selectedIndex >= working.length) selectedIndex = 0;
    }

    function selectedOutput() {
        return (selectedIndex >= 0 && selectedIndex < working.length)
               ? working[selectedIndex] : null;
    }

    function mutateSelected(fn) {
        if (selectedIndex < 0 || selectedIndex >= working.length) return;
        const copy = working.slice();
        const cur = Object.assign({}, copy[selectedIndex]);
        fn(cur);
        copy[selectedIndex] = cur;
        working = copy;
    }

    Component.onCompleted: {
        MonitorService.refresh();
        reloadFromService();
    }

    Connections {
        target: MonitorService
        function onOutputsChanged() {
            // Only re-pull if we're idle (not in the middle of an
            // apply/confirm sequence); the post-apply refresh would
            // otherwise blow away the user's pending edits.
            if (!shell.confirmOpen && !MonitorService.applying)
                shell.reloadFromService();
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18
        focus: true
        Keys.onEscapePressed: shell.requestClose()

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
                text: ""
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: 28
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: I18n.t("monitors.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                }
                Text {
                    text: I18n.t("monitors.subtitle")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                }
            }
        }

        // ---- Canvas: drag-arrange ----
        Rectangle {
            id: canvasFrame
            anchors.top: header.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            height: 320
            radius: Theme.radius
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
            border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)
            border.width: 1
            clip: true

            // Inner padding inside the canvas. Bounding box of all
            // monitors is scaled to fit inside `canvasFrame.width -
            // 2*pad` × `canvasFrame.height - 2*pad`.
            readonly property int pad: 24

            // Compute total bounding box of every monitor in
            // working[]. Includes the rotated size — for transform
            // 90/270 the on-screen footprint is height × width.
            readonly property var bbox: {
                if (shell.working.length === 0)
                    return { x: 0, y: 0, w: 1, h: 1 };
                let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                for (const m of shell.working) {
                    const w = m.widthPx, h = m.heightPx;
                    if (m.positionX     < minX) minX = m.positionX;
                    if (m.positionY     < minY) minY = m.positionY;
                    if (m.positionX + w > maxX) maxX = m.positionX + w;
                    if (m.positionY + h > maxY) maxY = m.positionY + h;
                }
                return { x: minX, y: minY,
                         w: Math.max(1, maxX - minX),
                         h: Math.max(1, maxY - minY) };
            }

            // Pixel scale: px-on-canvas per px-of-virtual-screen. Pick
            // the limiting axis so the whole layout fits with padding.
            readonly property real scaleFactor: {
                if (!bbox || bbox.w <= 0 || bbox.h <= 0) return 0.05;
                const availW = canvasFrame.width  - 2 * canvasFrame.pad;
                const availH = canvasFrame.height - 2 * canvasFrame.pad;
                return Math.min(availW / bbox.w, availH / bbox.h);
            }

            // Centering offsets: distribute leftover space equally on
            // both sides of the scaled bbox so a 16:9 wide layout
            // sits in the middle of the canvas rather than hugging
            // the top-left corner.
            readonly property real offsetX:
                (canvasFrame.width  - bbox.w * scaleFactor) / 2
            readonly property real offsetY:
                (canvasFrame.height - bbox.h * scaleFactor) / 2

            // Helpers: virtual-px → canvas-px and back.
            function vxToCx(vx) {
                return (vx - bbox.x) * scaleFactor + canvasFrame.offsetX;
            }
            function vyToCy(vy) {
                return (vy - bbox.y) * scaleFactor + canvasFrame.offsetY;
            }
            function cxToVx(cx) {
                return (cx - canvasFrame.offsetX) / scaleFactor + bbox.x;
            }
            function cyToVy(cy) {
                return (cy - canvasFrame.offsetY) / scaleFactor + bbox.y;
            }

            Repeater {
                model: shell.working
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index

                    width:  Math.max(40, modelData.widthPx  * canvasFrame.scaleFactor)
                    height: Math.max(28, modelData.heightPx * canvasFrame.scaleFactor)
                    x: canvasFrame.vxToCx(modelData.positionX)
                    y: canvasFrame.vyToCy(modelData.positionY)
                    radius: Theme.radius
                    color: index === shell.selectedIndex
                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                           : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)
                    border.color: index === shell.selectedIndex ? Theme.accent
                                                                 : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.30)
                    border.width: index === shell.selectedIndex ? 2 : 1

                    MouseArea {
                        id: tileDrag
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        drag.target: tile
                        drag.minimumX: 0
                        drag.minimumY: 0
                        drag.maximumX: canvasFrame.width  - tile.width
                        drag.maximumY: canvasFrame.height - tile.height
                        onPressed: shell.selectedIndex = tile.index
                        onReleased: {
                            // Snap drag end to virtual pixels and
                            // write the new position into the working
                            // snapshot. Round to multiples of 10 for a
                            // friendlier "loose snap" experience.
                            const vx = Math.round(canvasFrame.cxToVx(tile.x) / 10) * 10;
                            const vy = Math.round(canvasFrame.cyToVy(tile.y) / 10) * 10;
                            const i = tile.index;
                            shell.mutateSelected(o => { o.positionX = vx; o.positionY = vy; });
                            // selectedIndex may have changed via onPressed; reselect i to be safe
                            shell.selectedIndex = i;
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.connector
                            color: Theme.fg
                            font.family: Theme.sansFamily
                            font.pixelSize: Theme.fontPx
                            font.bold: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.widthPx + "×" + tile.modelData.heightPx
                            color: Theme.fgDim
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontPxSmall
                        }
                    }
                }
            }
        }

        // ---- Per-output form ----
        Column {
            id: form
            anchors.top: canvasFrame.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Row {
                spacing: 12
                width: parent.width

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text {
                        text: I18n.t("monitors.output")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxSmall
                    }
                    Dropdown {
                        width: parent.width
                        model: shell.working
                        textRole: "connector"
                        currentIndex: shell.selectedIndex
                        onSelected: (i) => shell.selectedIndex = i
                    }
                }

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text {
                        text: I18n.t("monitors.mode")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxSmall
                    }
                    Dropdown {
                        width: parent.width
                        // Build mode list with a display label so the
                        // dropdown's header matches the row look. The
                        // mapped label includes a star on the
                        // EDID-preferred mode.
                        readonly property var modes:
                            shell.selectedOutput() ? shell.selectedOutput().modes.map((m, i) => ({
                                idx: i,
                                label: m.width + "×" + m.height + " @ " +
                                       MonitorService.fmtRefresh(m.refresh_rate) + " Hz" +
                                       (m.is_preferred ? "  ★" : "")
                            })) : []
                        model: modes
                        textRole: "label"
                        valueRole: "idx"
                        currentIndex: shell.selectedOutput() ? shell.selectedOutput().modeIndex : -1
                        onSelected: (i, item) => shell.mutateSelected(o => {
                            o.modeIndex = item.idx;
                            const src = shell.working[shell.selectedIndex];
                            // Pull the resolved mode object back in so
                            // the canvas tile resizes immediately.
                            o.mode = src.modes && src.modes[item.idx]
                                     ? src.modes[item.idx] : o.mode;
                            if (o.mode) {
                                o.widthPx  = o.mode.width;
                                o.heightPx = o.mode.height;
                            }
                        })
                    }
                }

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text {
                        text: I18n.t("monitors.scale")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxSmall
                    }
                    Dropdown {
                        width: parent.width
                        readonly property var choices: [
                            { v: 1.0,  label: "1.0×" },
                            { v: 1.25, label: "1.25×" },
                            { v: 1.5,  label: "1.5×" },
                            { v: 1.75, label: "1.75×" },
                            { v: 2.0,  label: "2.0×" }
                        ]
                        model: choices
                        textRole: "label"
                        valueRole: "v"
                        currentIndex: {
                            const cur = shell.selectedOutput();
                            if (!cur) return 0;
                            for (let i = 0; i < choices.length; i++) {
                                if (Math.abs(choices[i].v - cur.scale) < 0.001) return i;
                            }
                            return 0;
                        }
                        onSelected: (i, item) => shell.mutateSelected(o => { o.scale = item.v; })
                    }
                }
            }

            // ---- Row 2: transform + VRR ----
            // Transform dropdown carries the niri-JSON form
            // ("Normal" / "Flipped90") through unchanged; the kdl
            // writer translates to the kebab-case form niri expects.
            // VRR toggle is greyed out when the monitor reports it as
            // unsupported (vrr_supported=false in the niri JSON).
            Row {
                spacing: 12
                width: parent.width

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text {
                        text: I18n.t("monitors.transform")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxSmall
                    }
                    Dropdown {
                        width: parent.width
                        readonly property var choices: [
                            { v: "Normal",     label: I18n.t("monitors.transform.normal")      },
                            { v: "90",         label: I18n.t("monitors.transform.r90")         },
                            { v: "180",        label: I18n.t("monitors.transform.r180")        },
                            { v: "270",        label: I18n.t("monitors.transform.r270")        },
                            { v: "Flipped",    label: I18n.t("monitors.transform.flipped")     },
                            { v: "Flipped90",  label: I18n.t("monitors.transform.flipped90")   },
                            { v: "Flipped180", label: I18n.t("monitors.transform.flipped180")  },
                            { v: "Flipped270", label: I18n.t("monitors.transform.flipped270")  }
                        ]
                        model: choices
                        textRole: "label"
                        valueRole: "v"
                        currentIndex: {
                            const cur = shell.selectedOutput();
                            if (!cur) return 0;
                            for (let i = 0; i < choices.length; i++) {
                                if (choices[i].v === cur.transform) return i;
                            }
                            return 0;
                        }
                        onSelected: (i, item) => shell.mutateSelected(o => {
                            // Swap width/height when going to/from a
                            // 90/270 rotation so the canvas tile
                            // reflects the new on-screen footprint
                            // immediately. The dimensions live with
                            // the mode (portrait vs landscape pixel
                            // count), but the *displayed* width
                            // depends on rotation.
                            const oldRot = o.transform;
                            const newRot = item.v;
                            const isRotated = (t) => t === "90" || t === "270" ||
                                                     t === "Flipped90" || t === "Flipped270";
                            if (isRotated(oldRot) !== isRotated(newRot)) {
                                const tmp = o.widthPx;
                                o.widthPx  = o.heightPx;
                                o.heightPx = tmp;
                            }
                            o.transform = newRot;
                        })
                    }
                }

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text {
                        text: I18n.t("monitors.vrr")
                        color: Theme.fgDim
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPxSmall
                    }
                    Item {
                        width: parent.width
                        height: Theme.controlHeight
                        Toggle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            // Toggle's default content is the label +
                            // a switch; for the form row we already
                            // have a column label, so we use a short
                            // status label that mirrors the state.
                            label: {
                                const cur = shell.selectedOutput();
                                if (!cur) return "";
                                if (!cur.vrrSupported) return I18n.t("monitors.vrr.unsupported");
                                return cur.vrr ? I18n.t("monitors.vrr.on")
                                               : I18n.t("monitors.vrr.off");
                            }
                            enabled: {
                                const cur = shell.selectedOutput();
                                return !!cur && cur.vrrSupported;
                            }
                            checked: {
                                const cur = shell.selectedOutput();
                                return !!cur && cur.vrr;
                            }
                            onToggled: (b) => shell.mutateSelected(o => { o.vrr = b; })
                        }
                    }
                }

                // Reserve the third column so the VRR toggle aligns
                // with the Scale dropdown above and the row keeps a
                // consistent rhythm.
                Item {
                    width: (parent.width - 24) / 3
                    height: 1
                }
            }

            // Position read-out (read-only, follows canvas drags).
            Row {
                width: parent.width
                spacing: 12
                visible: shell.selectedOutput() !== null

                Text {
                    text: I18n.t("monitors.position") + ":"
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxSmall
                }
                Text {
                    text: shell.selectedOutput()
                          ? "x = " + shell.selectedOutput().positionX +
                            "  y = " + shell.selectedOutput().positionY
                          : ""
                    color: Theme.fg
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontPxSmall
                }
                Text {
                    text: shell.selectedOutput()
                          ? "  •  " + I18n.t("monitors.identifier") + ": " +
                            shell.selectedOutput().id
                          : ""
                    color: Theme.fgDim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontPxSmall
                    elide: Text.ElideRight
                    width: parent.width - 320
                }
            }

            // ---- Custom-KDL textbox ----
            // Free-form niri output settings (per-output `layout {}`,
            // `off`, `background-color`, `focus-at-startup`, ...).
            // Anything typed here is written verbatim inside this
            // output's block on Apply, and round-trips through the
            // panel: every reopen reads back what's currently in
            // monitors.kdl.
            Column {
                width: parent.width
                spacing: 6
                visible: shell.selectedOutput() !== null

                Text {
                    text: I18n.t("monitors.extras")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxSmall
                }
                Text {
                    width: parent.width
                    text: I18n.t("monitors.extras.hint")
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxSmall
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    width: parent.width
                    height: 120
                    radius: Theme.radius
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                    border.color: extrasEditor.activeFocus ? Theme.accent : Theme.fgDim
                    border.width: extrasEditor.activeFocus
                                  ? Theme.controlFocusBorderWidth
                                  : Theme.controlBorderWidth
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Flickable {
                        id: extrasFlick
                        anchors.fill: parent
                        anchors.margins: Theme.controlPadX
                        contentWidth:  extrasEditor.paintedWidth
                        contentHeight: extrasEditor.paintedHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: extrasEditor
                            width: extrasFlick.width
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontPxSmall
                            wrapMode: TextEdit.NoWrap
                            selectByMouse: true
                            activeFocusOnTab: true
                            persistentSelection: true
                            tabStopDistance: 4 * extrasEditor.font.pixelSize

                            // Pull the current snapshot's extras into
                            // the editor whenever the selection or
                            // working snapshot changes. _sync is a
                            // no-op when the text already matches, so
                            // it doesn't fight a user mid-typing.
                            function _sync() {
                                const cur = shell.selectedOutput();
                                const v = cur ? (cur.extras || "") : "";
                                if (extrasEditor.text !== v) extrasEditor.text = v;
                            }
                            Component.onCompleted: _sync()

                            Connections {
                                target: shell
                                function onSelectedIndexChanged() { extrasEditor._sync(); }
                                function onWorkingChanged()       { extrasEditor._sync(); }
                            }

                            onTextChanged: {
                                const cur = shell.selectedOutput();
                                if (!cur) return;
                                if ((cur.extras || "") === extrasEditor.text) return;
                                shell.mutateSelected(o => { o.extras = extrasEditor.text; });
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                visible: extrasEditor.text === "" && !extrasEditor.activeFocus
                                text: I18n.t("monitors.extras.placeholder")
                                color: Theme.fgDim
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxSmall
                                opacity: 0.7
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: true
                        cursorShape: Qt.IBeamCursor
                        onPressed: (mouse) => {
                            extrasEditor.forceActiveFocus();
                            mouse.accepted = false;
                        }
                    }
                }
            }
        }

        // ---- Footer ----
        Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            spacing: 10

            Button {
                label: I18n.t("monitors.cancel")
                variant: Button.Secondary
                onTriggered: {
                    shell.reloadFromService();
                    shell.requestClose();
                }
            }
            Button {
                label: I18n.t("monitors.apply")
                variant: Button.Primary
                enabled: shell.working.length > 0 && !shell.confirmOpen && !MonitorService.applying
                onTriggered: {
                    MonitorService.applyConfig(shell.working);
                    // Pop the confirm modal with a 10s countdown. The
                    // post-write refresh sets MonitorService.applying
                    // false a few hundred ms later; the countdown
                    // ticks regardless.
                    shell.countdown = 10;
                    shell.confirmOpen = true;
                    confirmTimer.start();
                }
            }
        }
    }

    // ---- Confirm-or-revert overlay ----
    Rectangle {
        id: confirmScrim
        anchors.fill: parent
        visible: shell.confirmOpen
        color: Qt.rgba(0, 0, 0, 0.6)

        MouseArea {
            anchors.fill: parent
            // Eat clicks so they don't fall through to the canvas.
            // Confirmation requires an explicit button press.
            preventStealing: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: 200
            radius: Theme.radius
            color: Theme.cardBg
            border.color: Theme.accent
            border.width: 2

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                Text {
                    width: parent.width
                    text: I18n.t("monitors.confirm.title")
                    color: Theme.fg
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPxLarge
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: I18n.t("monitors.confirm.body", shell.countdown)
                    color: Theme.fgDim
                    font.family: Theme.sansFamily
                    font.pixelSize: Theme.fontPx
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Button {
                        label: I18n.t("monitors.confirm.revert")
                        variant: Button.Urgent
                        onTriggered: {
                            confirmTimer.stop();
                            MonitorService.revert();
                            shell.confirmOpen = false;
                        }
                    }
                    Button {
                        label: I18n.t("monitors.confirm.keep")
                        variant: Button.Primary
                        onTriggered: {
                            confirmTimer.stop();
                            MonitorService.clearBackup();
                            shell.confirmOpen = false;
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            shell.countdown = shell.countdown - 1;
            if (shell.countdown <= 0) {
                confirmTimer.stop();
                MonitorService.revert();
                shell.confirmOpen = false;
            }
        }
    }
}
