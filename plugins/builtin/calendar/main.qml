import QtQuick
import Quickshell
import qs

// Calendar pill + month-grid popup. Based on Omarchy's calendar.qml with
// extras called for in the niri-setup Phase C list:
//   - ISO-8601 week-number column on the left
//   - Year-jump chevrons («/») flanking the month-jump chevrons (‹/›)
//   - Click the month/year label to jump back to today
//   - Locale-driven first day of week, weekday abbreviations, and
//     week-column header ("Wk"/"KW"/…). For German locales the week
//     starts Monday; for US English it starts Sunday. ISO week numbers
//     are computed from each row's Thursday so they stay consistent
//     across both layouts.
Item {
    id: root

    // Parent PanelWindow reference — used as the popup's anchor.window.
    property var barWindow: null

    // Latched once the popup has been opened — keeps the lazy-loaded
    // grid alive after close so subsequent opens are instant.
    property bool _everOpened: false

    property string format: "dddd HH:mm"

    property date now:       new Date()
    property date viewMonth: new Date()

    // All Qt locale lookups go through `loc` so a runtime change via
    // LanguagePicker re-tints month / weekday names. Bare `Qt.locale()`
    // returns the application's default, set ONCE from $LANG at
    // engine startup and doesn't respond to our I18n switch.
    readonly property var loc: Qt.locale(I18n.locale)

    // 0 = Sunday … 6 = Saturday in JS conventions. Qt returns
    // Qt::DayOfWeek (1=Monday..7=Sunday); coerce here to JS form.
    readonly property int firstDayOfWeek: {
        const v = loc.firstDayOfWeek;
        return v === 7 ? 0 : v;     // Qt.Sunday(7) → JS 0
    }

    // "Wk" / "KW" / "Sem" / etc. for the leftmost column header. Qt has
    // no built-in for this so we keep a small lookup; falls back to "Wk".
    readonly property string weekHeaderLabel: {
        const lang = I18n.locale;
        if (lang === "de") return "KW";
        if (lang === "fr") return "Sem";
        if (lang === "es") return "Sem";
        if (lang === "it") return "Set";
        if (lang === "nl") return "Wk";
        if (lang === "pt") return "Sem";
        return "Wk";
    }

    SystemClock {
        id: clockTimer
        precision: SystemClock.Minutes
        onDateChanged: root.now = clockTimer.date
    }

    function shiftMonth(delta) {
        const d = new Date(viewMonth);
        d.setDate(1);
        d.setMonth(d.getMonth() + delta);
        viewMonth = d;
    }
    function shiftYear(delta) {
        const d = new Date(viewMonth);
        d.setDate(1);
        d.setFullYear(d.getFullYear() + delta);
        viewMonth = d;
    }
    function jumpToToday() {
        viewMonth = new Date(root.now);
    }

    // ISO 8601 week number for a given Date.
    function isoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(),
                                    date.getMonth(),
                                    date.getDate()));
        const day = d.getUTCDay() || 7;       // Mon=1..Sun=7
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    }

    // 2-letter weekday abbreviation in the current locale. colIndex is
    // 0..6 where 0 = the first column (locale-dependent: Monday for DE,
    // Sunday for en_US).
    function dayHeaderLabel(colIndex) {
        const jsDay = (firstDayOfWeek + colIndex) % 7;       // 0=Sun..6=Sat
        const qtDay = jsDay === 0 ? 7 : jsDay;               // 1=Mon..7=Sun
        const name = loc.standaloneDayName(qtDay, Locale.ShortFormat);
        // German "Mo." → "Mo"; English "Mon" → "Mo"; trim trailing punctuation
        // / whitespace and clip to 2 chars for a tidy header.
        return String(name || "").replace(/[.\s]+$/, "").substring(0, 2);
    }

    implicitHeight: Theme.barHeight
    implicitWidth:  pill.implicitWidth

    BarPill {
        id: pill
        active: popover.popupOpen
        onClicked: {
            root.jumpToToday();
            popover.toggle();
            if (popover.popupOpen) root._everOpened = true;
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: loc.toString(root.now, root.format)
            color: Theme.fg
            font.family: Theme.sansFamily
            font.pixelSize: Theme.fontPx
        }
    }

    // ---------------- Popup ----------------
    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        implicitWidth:  360
        // Hard-coded height (header + day-header row + 6 week rows +
        // margins) so the popup surface gets the right size at
        // construction — gridCol lives inside a Loader and isn't built
        // until first open, so binding to its size would render the
        // popup window at 24 px tall for one frame.
        implicitHeight: 320

        readonly property int columnSpacing: 4
        readonly property real cellWidth:
            (implicitWidth - 2 * contentMargin - 7 * columnSpacing) / 8

        // Lazy-load the month grid — first popup open instantiates
        // the 42 day cells + 8 header cells, subsequent opens are free.
        Loader {
            anchors.fill: parent
            active: popover.popupOpen || root._everOpened
            sourceComponent: gridComponent
        }

        Component {
            id: gridComponent

        Column {
            id: gridCol
            anchors.fill: parent
            spacing: Theme.popoverSpacing

                // -------- Header: «  ‹  Month YYYY  ›  » --------
                Item {
                    width: parent.width
                    implicitHeight: 28

                    component NavButton: Rectangle {
                        property string glyph: ""
                        signal trigger()

                        width: 28; height: 24; radius: Theme.radius
                        color: ma.containsMouse ? Theme.hot : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: parent.glyph
                            color: Theme.fg
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.fontPx + 2
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.trigger()
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        NavButton {
                            glyph: "«"
                            onTrigger: root.shiftYear(-1)
                        }
                        NavButton {
                            glyph: "󰅁"   // nf-md-chevron_left
                            onTrigger: root.shiftMonth(-1)
                        }
                    }

                    Text {
                        id: monthLabel
                        anchors.centerIn: parent
                        // Explicit Locale.toString() to ensure German month
                        // names — Qt.formatDate's default locale isn't always
                        // the QApplication system locale in QML.
                        text: loc.toString(root.viewMonth, "MMMM yyyy")
                        color: Theme.fg
                        font.family: Theme.sansFamily
                        font.pixelSize: Theme.fontPx + 1
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: monthLabel
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.jumpToToday()
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        NavButton {
                            glyph: "󰅂"   // nf-md-chevron_right
                            onTrigger: root.shiftMonth(1)
                        }
                        NavButton {
                            glyph: "»"
                            onTrigger: root.shiftYear(1)
                        }
                    }
                }

                // -------- Day-of-week header --------
                Row {
                    spacing: popover.columnSpacing
                    Repeater {
                        // 8 cells: Wk + 7 locale-ordered days.
                        model: 8
                        delegate: Item {
                            required property int index
                            width:  popover.cellWidth
                            height: 18

                            readonly property bool isWeekCol: index === 0
                            readonly property string text:
                                isWeekCol ? root.weekHeaderLabel
                                          : root.dayHeaderLabel(index - 1)
                            readonly property int dayJs:
                                isWeekCol ? -1
                                          : (root.firstDayOfWeek + index - 1) % 7
                            readonly property bool isWeekend:
                                !isWeekCol && (dayJs === 0 || dayJs === 6)

                            Text {
                                anchors.centerIn: parent
                                text: parent.text
                                color: parent.isWeekCol || parent.isWeekend
                                       ? Theme.fgDim : Theme.fg
                                opacity: parent.isWeekCol ? 0.6 : 1.0
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx - 2
                                font.bold: true
                            }
                        }
                    }
                }

                // -------- 6 week rows × (Wk + 7 day) cells --------
                Column {
                    id: weeksCol
                    width: parent.width
                    spacing: popover.columnSpacing

                    readonly property var startOfMonth: {
                        const d = new Date(root.viewMonth);
                        d.setDate(1);
                        return d;
                    }
                    // Offset from startOfMonth back to that week's first
                    // day (firstDayOfWeek), in JS conventions.
                    readonly property int firstDayOffset:
                        (startOfMonth.getDay() - root.firstDayOfWeek + 7) % 7

                    Repeater {
                        model: 6
                        delegate: Row {
                            required property int index   // week row 0..5
                            spacing: popover.columnSpacing

                            // First visible date of this row
                            // (locale's firstDayOfWeek).
                            readonly property var weekStart: {
                                const d = new Date(weeksCol.startOfMonth);
                                d.setDate(d.getDate()
                                    - weeksCol.firstDayOffset
                                    + index * 7);
                                return d;
                            }
                            // Thursday of the same week, used for
                            // unambiguous ISO 8601 week number regardless
                            // of which day the locale's row starts on.
                            readonly property var rowThursday: {
                                const t = new Date(weekStart);
                                t.setDate(t.getDate()
                                    + ((4 - root.firstDayOfWeek + 7) % 7));
                                return t;
                            }

                            // Week-number cell.
                            Rectangle {
                                width:  popover.cellWidth
                                height: 28
                                radius: Theme.radius
                                color:  "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: root.isoWeek(parent.parent.rowThursday)
                                    color: Theme.fgDim
                                    font.family: Theme.sansFamily
                                    font.pixelSize: Theme.fontPx - 2
                                    opacity: 0.7
                                }
                            }

                            // 7 day cells.
                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    required property int index   // 0..6 within row

                                    readonly property var dayDate: {
                                        const d = new Date(parent.weekStart);
                                        d.setDate(d.getDate() + index);
                                        return d;
                                    }
                                    readonly property int dayJs:
                                        (root.firstDayOfWeek + index) % 7
                                    readonly property bool isWeekend:
                                        dayJs === 0 || dayJs === 6
                                    readonly property bool inMonth:
                                        dayDate.getMonth() === root.viewMonth.getMonth()
                                    readonly property bool isToday: {
                                        const n = root.now;
                                        return dayDate.getDate()     === n.getDate()
                                            && dayDate.getMonth()    === n.getMonth()
                                            && dayDate.getFullYear() === n.getFullYear();
                                    }

                                    width:  popover.cellWidth
                                    height: 28
                                    radius: Theme.radius
                                    color:  isToday ? Theme.fg : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: dayDate.getDate()
                                        color: isToday ? Theme.bg
                                              : !inMonth ? Theme.fgDim
                                              : isWeekend ? Theme.fgDim
                                              : Theme.fg
                                        opacity: inMonth ? 1.0 : 0.45
                                        font.family: Theme.sansFamily
                                        font.pixelSize: Theme.fontPx - 1
                                        font.bold: isToday
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
