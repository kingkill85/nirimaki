import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Weather widget. Bar pill (icon + temp) → popup with current conditions
// and 3-day forecast.
//
// Modelled on Omarchy's shell/plugins/bar/widgets/weatherFlyout.qml
// (modules-center placement, hero icon + temp + FEELS/WIND/HUMID columns,
// 3-day forecast row). Simplified: single Open-Meteo call per refresh
// (their flyout fans out to wttr.in + open-meteo + wttr.in/format=%l).
// Location is one-shot IP-geolocated via ipapi.co; falls back to Berlin
// if the network's slow or the service rate-limits.
Item {
    id: root

    property var barWindow: null
    property bool popupOpen: false

    // Latched once the popup has been opened — keeps the lazy-loaded
    // hero+forecast content alive after close so subsequent opens are
    // free.
    property bool _everOpened: false
    onPopupOpenChanged: if (popupOpen) _everOpened = true

    // Default to Berlin; refined by locationProc on startup.
    property real lat: 52.52
    property real lon: 13.41
    property string locationName: "Berlin"
    property bool locationKnown: false

    // Locale-driven default: US uses Fahrenheit, everyone else Celsius.
    readonly property bool useImperial:
        /^en_US/.test(String(Qt.locale().name || ""))

    property var current: null  // { temperature_2m, apparent_temperature, relative_humidity_2m, weather_code, wind_speed_10m }
    property var daily: null    // { time[], weather_code[], temperature_2m_max[], temperature_2m_min[] }

    function refresh() {
        // Don't fetch weather until we know the location — otherwise the
        // first call after login uses the default Berlin coords, which
        // are 250 km off from where this user actually is. The
        // locationProc.onExited handler retries this refresh once the
        // location resolves (or once we give up and fall back to Berlin).
        if (!locationKnown) {
            if (!locationProc.running) locationProc.running = true;
            return;
        }
        if (!weatherProc.running) {
            const url = "https://api.open-meteo.com/v1/forecast"
                + "?latitude=" + encodeURIComponent(lat)
                + "&longitude=" + encodeURIComponent(lon)
                + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
                + "&forecast_days=4"
                + "&timezone=auto"
                + (useImperial ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "");
            weatherProc.command = ["curl", "-fsS", "--max-time", "5", url];
            weatherProc.running = true;
        }
    }

    Process {
        id: locationProc
        // ipapi.co paywalls / rate-limits; ip-api.com only serves HTTPS to
        // paying customers. geojs.io is HTTPS, free, and unauthenticated.
        command: ["curl", "-fsS", "--max-time", "4", "https://get.geojs.io/v1/ip/geo.json"]
        stdout: StdioCollector {
            id: locOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const j = JSON.parse(String(locOut.text || ""));
                    const lat = parseFloat(j.latitude);
                    const lon = parseFloat(j.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        root.lat = lat;
                        root.lon = lon;
                        root.locationName = j.city || j.region || root.locationName;
                        root.locationKnown = true;
                    }
                } catch (e) {}
            }
        }
        // Fires on success AND failure (e.g. network not up yet at login).
        // On failure we still want to TRY the weather call — better to
        // show Berlin-default weather than nothing — but we re-arm
        // locationKnown=false next refresh isn't ours to handle: the
        // retry timer below kicks in again until current data lands.
        onExited: {
            if (root.locationKnown) {
                root.refresh();   // fetch weather at the resolved coords
            } else if (root.current === null) {
                // Location lookup failed AND we have no data yet — try
                // weather at the Berlin fallback so the user at least
                // sees something while the retry timer keeps probing.
                root.locationKnown = true;
                root.refresh();
            }
        }
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            id: wOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const j = JSON.parse(String(wOut.text || ""));
                    if (j.current) root.current = j.current;
                    if (j.daily)   root.daily = j.daily;
                } catch (e) {
                    // Keep last-good data if the API hiccups.
                }
            }
        }
    }

    Timer {
        // Fast retry until the first successful weather fetch (handles the
        // "logged in before network was up" case). Once data lands, back
        // off to a normal 15 min cadence.
        interval: root.current === null ? 30 * 1000 : 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Open-Meteo WMO weather code → nf-md weather glyph.
    function iconForCode(code) {
        const c = parseInt(code, 10);
        if (c === 0)                     return "󰖙"; // sunny
        if (c === 1 || c === 2)          return "󰖕"; // partly cloudy
        if (c === 3)                     return "󰖐"; // cloudy
        if (c === 45 || c === 48)        return "󰖑"; // fog
        if (c >= 51 && c <= 57)          return "󰖖"; // drizzle
        if (c >= 61 && c <= 67)          return "󰖖"; // rain
        if (c >= 71 && c <= 77)          return "󰖘"; // snow
        if (c >= 80 && c <= 82)          return "󰖗"; // rain showers
        if (c === 85 || c === 86)        return "󰖘"; // snow showers
        if (c >= 95 && c <= 99)          return "󰙾"; // thunderstorm
        return "󰖕";
    }

    readonly property string icon:
        current ? iconForCode(current.weather_code) : ""
    readonly property int tempInt:
        current && current.temperature_2m !== undefined
            ? Math.round(current.temperature_2m) : 0
    readonly property int feelsInt:
        current && current.apparent_temperature !== undefined
            ? Math.round(current.apparent_temperature) : 0
    readonly property string unitLetter: useImperial ? "F" : "C"
    readonly property string windStr:
        current && current.wind_speed_10m !== undefined
            ? Math.round(current.wind_speed_10m) + (useImperial ? " mph" : " km/h")
            : ""
    readonly property string humidStr:
        current && current.relative_humidity_2m !== undefined
            ? current.relative_humidity_2m + "%" : ""

    readonly property var forecastDays: {
        if (!daily || !daily.time) return [];
        const out = [];
        const today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        for (let i = 0; i < daily.time.length && out.length < 3; i++) {
            if (daily.time[i] <= today) continue;
            out.push({
                date: daily.time[i],
                max:  Math.round(daily.temperature_2m_max[i]),
                min:  Math.round(daily.temperature_2m_min[i]),
                code: daily.weather_code[i]
            });
        }
        return out;
    }

    function dayName(dateString) {
        if (!dateString) return "";
        const d = new Date(dateString + "T12:00:00");
        if (isNaN(d.getTime())) return "";
        // Locale.toString respects the user's locale (de_DE → "Mo", "Di",
        // …); Qt.formatDate's default locale is sometimes C.
        return Qt.locale().toString(d, "ddd");
    }

    // Stat-label translations live in ~/.config/quickshell/i18n/<locale>.json
    // (`weather.feels` / `weather.wind` / `weather.humid`). To add a
    // new locale, drop a new <xx>.json there.

    // ---------------- Bar trigger ----------------
    visible: current !== null
    implicitHeight: Theme.barHeight
    implicitWidth:  visible ? pill.width : 0

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barHeight - 2 * Theme.padY
        width:  rowLabel.implicitWidth + 2 * Theme.padX
        radius: Theme.radius
        color:  (hover.containsMouse || root.popupOpen) ? Theme.hot : "transparent"

        Row {
            id: rowLabel
            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                color: Theme.fg
                font.family: Theme.iconFamily
                font.pixelSize: Theme.iconPx
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.current ? (root.tempInt + "°") : ""
                color: Theme.fg
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPx
                opacity: 0.85
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton) {
                    root.refresh();
                } else {
                    root.popupOpen = !root.popupOpen;
                    if (root.popupOpen) root.refresh();
                }
            }
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
                // Compositor dismissed (outside-click / Escape) — sync
                // popupOpen back so the binding doesn't re-show us.
                if (root.popupOpen) root.popupOpen = false;
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.popupOpen = false
        }

        implicitWidth:  480
        // Hard-coded height (hero row + divider + forecast row + margins)
        // so the popup surface gets the right size at construction.
        // Pre-refactor this bound to card.implicitHeight, but card now
        // lives inside a Loader and isn't built until first open.
        implicitHeight: 200

        Rectangle {
            anchors.fill: parent
            color: Theme.cardBg
            border.color: Theme.cardBorderColor
            border.width: Theme.cardBorderWidth
        }

        // Lazy-load hero + forecast — first popup open builds the
        // ~3-day forecast Repeater + Row layouts, subsequent opens free.
        Loader {
            anchors.fill: parent
            active: root.popupOpen || root._everOpened
            sourceComponent: cardComponent
        }

        Component {
            id: cardComponent

        Column {
            id: card
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            // -------- Hero row --------
            Item {
                width: parent.width
                height: Math.max(heroLeft.height, heroRight.height)

                Row {
                    id: heroLeft
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.icon || "—"
                        color: Theme.fg
                        font.family: Theme.iconFamily
                        font.pixelSize: 64
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            id: tempBig
                            text: root.current ? String(root.tempInt) : "—"
                            color: Theme.fg
                            font.family: Theme.monoFamily
                            font.pixelSize: 56
                            font.bold: true
                        }
                        Text {
                            text: root.current ? ("°" + root.unitLetter) : ""
                            color: Theme.fg
                            font.family: Theme.monoFamily
                            font.pixelSize: 22
                            anchors.top: tempBig.top
                            anchors.topMargin: 10
                        }
                    }
                }

                Column {
                    id: heroRight
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Row {
                        visible: root.locationName !== ""
                        spacing: 6
                        anchors.right: parent.right

                        Text {
                            text: ""  // nf-fa-map_marker
                            color: Theme.fgDim
                            font.family: Theme.iconFamily
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.locationName.toUpperCase()
                            color: Theme.fgDim
                            font.family: Theme.monoFamily
                            font.pixelSize: 12
                            font.letterSpacing: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        visible: !!root.current
                        spacing: 28
                        anchors.right: parent.right

                        Column {
                            spacing: 4
                            Text {
                                text: I18n.t("weather.feels")
                                color: Theme.fgDim
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxSmall
                                font.letterSpacing: 1
                            }
                            Text {
                                text: root.feelsInt + "°"
                                color: Theme.fg
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxMedium
                            }
                        }
                        Column {
                            spacing: 4
                            Text {
                                text: I18n.t("weather.wind")
                                color: Theme.fgDim
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxSmall
                                font.letterSpacing: 1
                            }
                            Text {
                                text: root.windStr
                                color: Theme.fg
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxMedium
                            }
                        }
                        Column {
                            spacing: 4
                            Text {
                                text: I18n.t("weather.humid")
                                color: Theme.fgDim
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxSmall
                                font.letterSpacing: 1
                            }
                            Text {
                                text: root.humidStr
                                color: Theme.fg
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontPxMedium
                            }
                        }
                    }
                }
            }

            // -------- "Fetching" placeholder --------
            Text {
                visible: !root.current
                text: I18n.t("weather.fetching")
                color: Theme.fgDim
                font.family: Theme.monoFamily
                font.pixelSize: 11
                font.italic: true
            }

            // -------- Divider --------
            Rectangle {
                visible: root.forecastDays.length > 0
                width: parent.width
                height: 1
                color: Theme.fg
                opacity: 0.12
            }

            // -------- Forecast row --------
            Item {
                visible: root.forecastDays.length > 0
                width: parent.width
                height: forecastRow.height

                Row {
                    id: forecastRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 42

                    Repeater {
                        model: root.forecastDays

                        Row {
                            required property var modelData
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.iconForCode(modelData.code)
                                color: Theme.fg
                                font.family: Theme.iconFamily
                                font.pixelSize: 26
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: root.dayName(modelData.date).toUpperCase()
                                    color: Theme.fgDim
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fontPxSmall
                                    font.letterSpacing: 1
                                }
                                Row {
                                    spacing: 6
                                    Text {
                                        text: modelData.max + "°"
                                        color: Theme.fg
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        text: modelData.min + "°"
                                        color: Theme.fgDim
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 12
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
}
