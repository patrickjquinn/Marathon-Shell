pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Shapes
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/Weather.js" as Weather

// The weather in full, over the Hub: now, the next day by the hour, ten days,
// and the details. Back closes it, or the place search first.
Item {
    id: sheet

    property bool open: false
    property bool choosing: false

    readonly property var forecast: WeatherClient.forecast
    readonly property var current: forecast.current || null
    readonly property var location: forecast.location || ({})
    readonly property var daily: forecast.daily || []
    readonly property int offset: forecast.timezone_offset || 0
    readonly property bool fahrenheit: WeatherClient.fahrenheit
    readonly property bool twelveHour: /a/i.test(Qt.locale().timeFormat(Locale.ShortFormat))
    readonly property var weekdays: [0, 1, 2, 3, 4, 5, 6].map(d => Qt.locale().dayName(d, Locale.ShortFormat))

    // True when it closed something.
    function back() {
        if (choosing) {
            choosing = false;
            return true;
        }
        if (open) {
            open = false;
            return true;
        }
        return false;
    }

    function temp(c) {
        return Weather.temperature(c, fahrenheit);
    }

    // Warm and cold, for the ten-day bars: blue under 0 °C to red over 30 °C.
    function tempColor(c) {
        const stops = [[-10, "#6e9cf7"], [0, "#5ac8fa"], [10, "#7fd3a0"], [20, "#ffd36b"], [30, "#ff9b53"], [40, "#ff5e57"]];
        for (let i = 1; i < stops.length; ++i) {
            if (c <= stops[i][0]) {
                const a = stops[i - 1], b = stops[i];
                return Qt.tint(a[1], Qt.alpha(b[1], Math.max(0, Math.min(1, (c - a[0]) / (b[0] - a[0])))));
            }
        }
        return stops[stops.length - 1][1];
    }

    onOpenChanged: {
        if (open)
            WeatherClient.refresh();
        else
            choosing = false;
    }

    visible: x < width
    x: open ? 0 : width

    Behavior on x {
        NumberAnimation {
            duration: MMotion.durationFor("entrance")
            easing.type: Easing.OutCubic
        }
    }

    KeelAmbienceBackground {
        width: sheet.Window.width
        height: sheet.Window.height
        wallpaper: AmbienceService.wallpaperUrl
        toneOpacity: 0.62
        light: AmbienceService.light
    }

    // Swallow taps so the Hub underneath stays still.
    MouseArea {
        anchors.fill: parent
    }

    Silica.SilicaFlickable {
        id: flick

        objectName: "weatherFlick"
        anchors.fill: parent
        visible: !sheet.choosing
        contentHeight: content.height
        clip: true

        Silica.PullDownMenu {
            Silica.MenuItem {
                text: qsTr("Choose a place")
                onClicked: sheet.choosing = true
            }
            Silica.MenuItem {
                visible: sheet.location.automatic === false
                text: qsTr("Use my location")
                onClicked: WeatherClient.setAutomatic()
            }
            Silica.MenuItem {
                text: qsTr("Refresh")
                onClicked: WeatherClient.refresh()
            }
        }

        Column {
            id: content

            width: parent.width
            topPadding: Constants.statusBarHeight
            bottomPadding: Silica.Theme.paddingLarge * 2

            Silica.PageHeader {
                title: sheet.location.name || qsTr("Weather")
                description: sheet.location.automatic ? qsTr("Current location") : (sheet.location.region || "")
            }

            // ── Now ─────────────────────────────────────────────
            Item {
                id: hero

                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                height: Math.max(heroSky.height, heroText.height)
                visible: sheet.current !== null

                GlyphIcon {
                    id: heroSky

                    name: sheet.current ? Weather.glyph(sheet.current.symbol, ((sheet.forecast.hourly || [])[0] || {}).is_day) : ""
                    size: Silica.Theme.itemSizeHuge * 1.2
                    color: Silica.Theme.primaryColor
                }
                Column {
                    id: heroText

                    anchors.right: parent.right
                    width: parent.width - heroSky.width

                    Silica.Label {
                        objectName: "heroTemperature"
                        anchors.right: parent.right
                        text: sheet.current ? sheet.temp(sheet.current.temperature) : ""
                        font.pixelSize: Silica.Theme.fontSizeHuge * 1.8
                        font.family: Silica.Theme.fontFamilyHeading
                        font.weight: Font.ExtraLight
                    }
                    Silica.Label {
                        anchors.right: parent.right
                        text: sheet.current ? Weather.condition(sheet.current.symbol) : ""
                        font.pixelSize: Silica.Theme.fontSizeLarge
                        color: Silica.Theme.highlightColor
                    }
                    Silica.Label {
                        anchors.right: parent.right
                        text: {
                            if (!sheet.current)
                                return "";
                            const parts = [qsTr("Feels like %1").arg(sheet.temp(sheet.current.apparent))];
                            if (sheet.daily.length > 0)
                                parts.push(qsTr("H %1 L %2").arg(sheet.temp(sheet.daily[0].high)).arg(sheet.temp(sheet.daily[0].low)));
                            return parts.join(" · ");
                        }
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        color: Silica.Theme.secondaryColor
                    }
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                topPadding: Silica.Theme.paddingLarge
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignRight
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                text: Weather.outlook(sheet.forecast.hourly, Date.now() / 1000, sheet.offset, sheet.twelveHour)
            }

            // Nothing yet: say why, and offer the way out.
            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: sheet.current === null
                wrapMode: Text.Wrap
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                text: WeatherClient.state === "no-location" ? qsTr("Your location isn't known yet. Pull down to choose a place.") : WeatherClient.state === "offline" ? qsTr("No connection. The weather will come when you're back online.") : WeatherClient.state === "updating" ? qsTr("Getting the weather…") : qsTr("The weather isn't available right now.")
            }

            // ── By the hour ─────────────────────────────────────
            Silica.SectionHeader {
                visible: sheet.current !== null
                text: qsTr("Next 24 hours")
            }
            WeatherHourlyChart {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                height: implicitHeight
                visible: sheet.current !== null
                curveHeight: Silica.Theme.itemSizeMedium
                readonly property int columns: Math.max(6, Math.min(12, Math.floor(width / Silica.Theme.itemSizeExtraSmall)))
                hours: Weather.upcoming(sheet.forecast.hourly, Date.now() / 1000, columns, Math.ceil(24 / columns))
                offset: sheet.offset
                fahrenheit: sheet.fahrenheit
                twelveHour: sheet.twelveHour
            }

            // ── Ten days ────────────────────────────────────────
            Silica.SectionHeader {
                visible: sheet.daily.length > 0
                text: qsTr("%n-day forecast", "", sheet.daily.length)
            }
            Repeater {
                model: sheet.daily

                Item {
                    id: day

                    required property var modelData
                    required property int index

                    readonly property var span: Weather.span(modelData, sheet.daily)

                    x: Silica.Theme.horizontalPageMargin
                    width: content.width - 2 * x
                    height: Silica.Theme.itemSizeSmall

                    Silica.Label {
                        id: dayName

                        width: Silica.Theme.itemSizeMedium
                        anchors.verticalCenter: parent.verticalCenter
                        text: day.index === 0 ? qsTr("Today") : Weather.weekday(day.modelData.date, sheet.weekdays)
                        color: day.index === 0 ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    }
                    GlyphIcon {
                        id: daySky

                        anchors.left: dayName.right
                        anchors.verticalCenter: parent.verticalCenter
                        name: Weather.glyph(day.modelData.symbol, true)
                        size: Silica.Theme.iconSizeMedium
                        color: Silica.Theme.primaryColor
                    }
                    Silica.Label {
                        id: dayRain

                        anchors.left: daySky.right
                        anchors.leftMargin: Silica.Theme.paddingSmall
                        anchors.verticalCenter: parent.verticalCenter
                        width: Silica.Theme.itemSizeExtraSmall
                        text: (day.modelData.precipitation_probability || 0) >= 20 ? day.modelData.precipitation_probability + "%" : ""
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        color: Silica.Theme.highlightColor
                    }
                    Silica.Label {
                        id: dayLow

                        anchors.left: dayRain.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Silica.Theme.itemSizeExtraSmall * 0.8
                        horizontalAlignment: Text.AlignRight
                        text: sheet.temp(day.modelData.low)
                        color: Silica.Theme.secondaryColor
                    }
                    Rectangle {
                        id: track

                        anchors.left: dayLow.right
                        anchors.right: dayHigh.left
                        anchors.margins: Silica.Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.max(4, Math.round(Silica.Theme.paddingSmall))
                        radius: height / 2
                        color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.12)

                        Rectangle {
                            x: track.width * day.span.from
                            width: Math.max(track.height, track.width * (day.span.to - day.span.from))
                            height: track.height
                            radius: track.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: sheet.tempColor(day.modelData.low)
                                }
                                GradientStop {
                                    position: 1
                                    color: sheet.tempColor(day.modelData.high)
                                }
                            }
                        }
                        // Today: where the temperature is now.
                        Rectangle {
                            readonly property var now: sheet.current ? Weather.span({
                                "low": sheet.current.temperature,
                                "high": sheet.current.temperature
                            }, sheet.daily).from : 0

                            visible: day.index === 0 && sheet.current !== null
                            width: track.height * 2
                            height: width
                            radius: width / 2
                            x: Math.max(0, Math.min(track.width, track.width * now)) - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Silica.Theme.primaryColor
                            border.color: Silica.Theme.rgba("black", 0.4)
                            border.width: 1
                        }
                    }
                    Silica.Label {
                        id: dayHigh

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Silica.Theme.itemSizeExtraSmall * 0.8
                        horizontalAlignment: Text.AlignRight
                        text: sheet.temp(day.modelData.high)
                    }
                }
            }

            // ── Details ─────────────────────────────────────────
            Silica.SectionHeader {
                visible: sheet.current !== null
                text: qsTr("Details")
            }
            Grid {
                id: tiles

                readonly property real tileWidth: (width - spacing) / 2

                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                columns: 2
                spacing: Silica.Theme.paddingMedium
                visible: sheet.current !== null

                WeatherTile {
                    width: tiles.tileWidth
                    glyph: "wind"
                    title: qsTr("Wind")
                    value: sheet.current ? Weather.speed(sheet.current.wind_speed, WeatherClient.milesPerHour) : ""
                    detail: sheet.current ? (sheet.current.wind_gust !== null && sheet.current.wind_gust !== undefined ? qsTr("From the %1, gusts %2").arg(Weather.compass(sheet.current.wind_direction)).arg(Weather.speed(sheet.current.wind_gust, WeatherClient.milesPerHour)) : qsTr("From the %1").arg(Weather.compass(sheet.current.wind_direction))) : ""

                    // The arrow points where the wind blows to.
                    Item {
                        width: Silica.Theme.iconSizeLarge
                        height: width

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.3)
                            border.width: 1
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            name: "arrow-up"
                            size: Silica.Theme.iconSizeSmallPlus
                            color: Silica.Theme.highlightColor
                            rotation: sheet.current ? sheet.current.wind_direction + 180 : 0
                        }
                    }
                }
                WeatherTile {
                    width: tiles.tileWidth
                    glyph: "drop"
                    title: qsTr("Humidity")
                    value: sheet.current && sheet.current.humidity !== null ? Math.round(sheet.current.humidity) + "%" : "–"
                    detail: sheet.current && sheet.current.dew_point !== null ? qsTr("Dew point %1").arg(sheet.temp(sheet.current.dew_point)) : ""
                }
                WeatherTile {
                    id: uvTile

                    readonly property real uv: sheet.daily.length > 0 && sheet.daily[0].uv_max !== null ? sheet.daily[0].uv_max : (sheet.current ? sheet.current.uv_index || 0 : 0)

                    width: tiles.tileWidth
                    glyph: "sun"
                    title: qsTr("UV index")
                    value: String(Math.round(uv))
                    detail: qsTr("%1 today").arg(Weather.uvLevel(uv))

                    Rectangle {
                        width: tiles.tileWidth - 2 * Silica.Theme.paddingLarge
                        height: Math.max(4, Math.round(Silica.Theme.paddingSmall))
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: "#7fd3a0"
                            }
                            GradientStop {
                                position: 0.3
                                color: "#ffd36b"
                            }
                            GradientStop {
                                position: 0.6
                                color: "#ff9b53"
                            }
                            GradientStop {
                                position: 0.85
                                color: "#ff5e57"
                            }
                            GradientStop {
                                position: 1
                                color: "#b48cff"
                            }
                        }

                        Rectangle {
                            width: parent.height * 2
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * Math.min(1, uvTile.uv / 11) - width / 2
                            color: Silica.Theme.primaryColor
                            border.color: Silica.Theme.rgba("black", 0.4)
                            border.width: 1
                        }
                    }
                }
                WeatherTile {
                    width: tiles.tileWidth
                    glyph: "umbrella"
                    title: qsTr("Precipitation")
                    value: sheet.daily.length > 0 && sheet.daily[0].precipitation !== null ? qsTr("%1 mm").arg(Math.round(sheet.daily[0].precipitation * 10) / 10) : "–"
                    detail: qsTr("Today")
                }
                WeatherTile {
                    width: tiles.tileWidth
                    glyph: "gauge"
                    title: qsTr("Pressure")
                    value: sheet.current && sheet.current.pressure !== null ? qsTr("%1 hPa").arg(Math.round(sheet.current.pressure)) : "–"
                    detail: sheet.current && sheet.current.cloud_cover !== null ? qsTr("Cloud cover %1%").arg(Math.round(sheet.current.cloud_cover)) : ""
                }
                WeatherTile {
                    id: sunTile

                    readonly property var today: sheet.daily.length > 0 ? sheet.daily[0] : null
                    readonly property real progress: today && today.sunrise && today.sunset ? Math.max(0, Math.min(1, (Date.now() / 1000 - today.sunrise) / (today.sunset - today.sunrise))) : 0

                    width: tiles.tileWidth
                    glyph: "sun-horizon"
                    title: qsTr("Sunrise")
                    value: today && today.sunrise ? Weather.clock(today.sunrise, sheet.offset, sheet.twelveHour) : "–"
                    detail: today && today.sunset ? qsTr("Sunset %1").arg(Weather.clock(today.sunset, sheet.offset, sheet.twelveHour)) : ""

                    // The day's arc, and the sun on it.
                    Item {
                        id: arc

                        width: tiles.tileWidth - 2 * Silica.Theme.paddingLarge
                        height: width / 3
                        visible: sunTile.today !== null && !!sunTile.today.sunrise

                        Shape {
                            anchors.fill: parent

                            ShapePath {
                                strokeColor: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.3)
                                strokeWidth: 1
                                strokeStyle: ShapePath.DashLine
                                fillColor: "transparent"
                                startX: 0
                                startY: arc.height

                                PathArc {
                                    x: arc.width
                                    y: arc.height
                                    radiusX: arc.width / 2
                                    radiusY: arc.height
                                }
                            }
                        }
                        Rectangle {
                            readonly property real angle: Math.PI * (1 - sunTile.progress)

                            width: Silica.Theme.paddingLarge
                            height: width
                            radius: width / 2
                            x: arc.width / 2 + Math.cos(angle) * arc.width / 2 - width / 2
                            y: arc.height - Math.sin(angle) * arc.height - height / 2
                            color: "#ffd36b"
                        }
                    }
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                topPadding: Silica.Theme.paddingLarge * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Silica.Theme.fontSizeTiny
                color: Silica.Theme.secondaryColor
                text: {
                    const parts = [];
                    if (sheet.forecast.updated)
                        parts.push(qsTr("Updated %1").arg(Weather.clock(sheet.forecast.updated, sheet.offset, sheet.twelveHour)));
                    parts.push(qsTr("Forecast: %1 · Places: © OpenStreetMap").arg(sheet.forecast.attribution || "MET Norway"));
                    return parts.join("\n");
                }
            }
        }

        Silica.VerticalScrollDecorator {}
    }

    // ── Choosing a place ────────────────────────────────────────
    Column {
        id: chooser

        property var places: []
        property string error: ""
        property bool searching: false

        anchors.fill: parent
        topPadding: Constants.statusBarHeight
        visible: sheet.choosing

        Silica.PageHeader {
            title: qsTr("Choose a place")
        }
        Silica.SearchField {
            id: query

            objectName: "weatherSearch"
            width: parent.width
            placeholderText: qsTr("City or town")
            // Nominatim asks for searches on submit, never as you type.
            Keys.onReturnPressed: {
                if (text.trim().length === 0)
                    return;
                chooser.searching = true;
                chooser.error = "";
                WeatherClient.search(text.trim());
            }
        }
        Silica.BackgroundItem {
            width: parent.width
            height: Silica.Theme.itemSizeSmall
            onClicked: {
                WeatherClient.setAutomatic();
                sheet.choosing = false;
            }

            GlyphIcon {
                id: here

                x: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                name: "crosshair"
                size: Silica.Theme.iconSizeSmallPlus
                color: Silica.Theme.highlightColor
            }
            Silica.Label {
                anchors.left: here.right
                anchors.leftMargin: Silica.Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Use my location")
                color: Silica.Theme.highlightColor
            }
        }
        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: text !== ""
            wrapMode: Text.Wrap
            color: Silica.Theme.secondaryHighlightColor
            text: chooser.searching ? qsTr("Searching…") : chooser.error
        }
        Repeater {
            model: chooser.places

            Silica.BackgroundItem {
                id: place

                required property var modelData

                width: chooser.width
                height: Silica.Theme.itemSizeMedium
                onClicked: {
                    WeatherClient.setLocation(place.modelData);
                    sheet.choosing = false;
                }

                Column {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        width: parent.width
                        truncationMode: Silica.TruncationMode.Fade
                        text: place.modelData.name
                    }
                    Silica.Label {
                        width: parent.width
                        truncationMode: Silica.TruncationMode.Fade
                        text: place.modelData.region || ""
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        color: Silica.Theme.secondaryColor
                    }
                }
            }
        }

        Connections {
            function onSearchFinished(places, error) {
                chooser.searching = false;
                chooser.places = places;
                chooser.error = error !== "" ? qsTr("Couldn't search: %1").arg(error) : places.length === 0 ? qsTr("No places found") : "";
            }

            target: WeatherClient
        }
    }

    onChoosingChanged: {
        if (choosing) {
            chooser.places = [];
            chooser.error = "";
            query.text = "";
            query.forceActiveFocus();
        }
    }
}
