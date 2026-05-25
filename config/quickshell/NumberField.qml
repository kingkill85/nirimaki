import QtQuick

// Numeric variant of TextField — clamps to [minimum, maximum], rounds
// to int when `integer: true`, exposes `value: real` separately from
// `text` so callers don't have to parse.
//
//   NumberField {
//       minimum: 0; maximum: 600; integer: true
//       value:    Config.value("idle.lock", 300)
//       suffix:   " s"
//       onValueCommitted: (v) => Config.setValue("idle.lock", v)
//   }
//
// `valueCommitted` fires on editingFinished (focus loss or Return) so
// transient digits-mid-type don't write back to settings.
TextField {
    id: root

    property real value: 0
    property real minimum: 0
    property real maximum: Number.MAX_VALUE
    property bool integer: false
    property string suffix: ""

    signal valueCommitted(real value)

    function _format(v) {
        const clamped = Math.max(minimum, Math.min(maximum, v));
        return integer ? String(Math.round(clamped))
                       : String(clamped);
    }
    function _parse(s) {
        const raw = String(s || "").replace(suffix, "").trim();
        const n = integer ? parseInt(raw, 10) : parseFloat(raw);
        return isNaN(n) ? minimum : Math.max(minimum, Math.min(maximum, n));
    }

    onValueChanged: {
        const formatted = _format(value) + (suffix ? suffix : "");
        if (text !== formatted) text = formatted;
    }
    Component.onCompleted: {
        const formatted = _format(value) + (suffix ? suffix : "");
        if (text !== formatted) text = formatted;
    }

    inputMethodHints: integer ? Qt.ImhDigitsOnly : Qt.ImhFormattedNumbersOnly

    onEditingFinished: {
        const parsed = _parse(text);
        if (parsed !== value) {
            value = parsed;
            valueCommitted(parsed);
        }
        // Renormalize text in case user typed "5 s" or "5":
        text = _format(parsed) + (suffix ? suffix : "");
    }
}
