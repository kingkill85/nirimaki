import QtQuick

// Horizontal slider — drag, click-to-set, scroll-wheel-to-adjust.
//
//   PanelSlider {
//       width: parent.width
//       value: AudioService.volume
//       step:  0.05
//       onMoved:    (v) => AudioService.setVolumeLive(v)
//       onReleased: (v) => AudioService.commitVolume(v)
//   }
//
// `value` is the authoritative bound value. While dragging we surface
// changes on `liveValue` / `moved(v)` without writing back to `value`
// so consumers can choose whether to commit per-frame or only on
// release (Pipewire sink-volume is fine per-frame; an HTTP-backed
// setting wants release-only).
//
// `integer: true` rounds every emit to the nearest int (NumberField,
// some count-style settings). `step` is the keyboard / scroll-wheel
// granularity; pointer drags stay continuous.
Item {
    id: root

    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property bool integer: false

    property color trackColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)
    property color fillColor:  Theme.accent
    property color knobColor:  Theme.fg
    property color knobBorder: Theme.accent

    // Mutated while dragging; mirrors `value` otherwise.
    property real liveValue: value
    property bool dragging: false

    signal moved(real value)
    signal released(real value)

    onValueChanged: if (!dragging) liveValue = value

    implicitWidth:  200
    implicitHeight: Math.max(22, Theme.sliderKnobSize + 6)

    readonly property real _range: Math.max(0.0001, maximum - minimum)
    readonly property real _progress: Math.max(0, Math.min(1, (liveValue - minimum) / _range))
    readonly property bool _hot: ma.containsMouse || root.dragging

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left:  parent.left
        anchors.right: parent.right
        height: Theme.sliderTrackHeight
        radius: height / 2
        color:  root.trackColor

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            height: parent.height
            radius: parent.radius
            width: parent.width * root._progress
            color: root.fillColor
            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        id: knob
        width:  Theme.sliderKnobSize
        height: Theme.sliderKnobSize
        radius: width / 2
        color: root.knobColor
        border.color: root.knobBorder
        border.width: 1
        anchors.verticalCenter: track.verticalCenter
        x: Math.max(0, Math.min(track.width - width,
                                track.width * root._progress - width / 2))
        scale: root._hot ? 1.15 : 1.0

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -6   // forgiving hit area
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function _valueFromX(x) {
            const clamped = Math.max(0, Math.min(track.width, x));
            let v = root.minimum + (clamped / track.width) * root._range;
            if (root.integer) v = Math.round(v);
            return Math.max(root.minimum, Math.min(root.maximum, v));
        }

        onPressed: (mouse) => {
            root.dragging = true;
            const v = _valueFromX(mouse.x);
            root.liveValue = v;
            root.moved(v);
        }
        onPositionChanged: (mouse) => {
            if (!root.dragging) return;
            const v = _valueFromX(mouse.x);
            root.liveValue = v;
            root.moved(v);
        }
        onReleased: () => {
            root.dragging = false;
            root.released(root.liveValue);
            root.liveValue = root.value;
        }
        onWheel: (wheel) => {
            const d = wheel.angleDelta.y > 0 ? root.step : -root.step;
            let v = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + d));
            if (root.integer) v = Math.round(v);
            root.liveValue = v;
            root.moved(v);
            root.released(v);
            wheel.accepted = true;
        }
    }
}
