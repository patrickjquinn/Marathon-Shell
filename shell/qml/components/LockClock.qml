pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import "../core/Weather.js" as Weather

// The lock screen's time, weekday, weather and date. The empty task switcher
// shows the same block in the same place.
Item {
    id: root

    // Music below: a smaller clock, with the date beside the weekday.
    property bool mediaActive: false
    // Music or notifications below: the block sits higher.
    property bool crowded: mediaActive
    // Short/square screens (HackberryPi, Q25) place by height, not design px.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    // A tall phone: spaced out and larger.
    readonly property bool tallLayout: !compactLayout && Constants.isTallScreen
    // Where the top of the clock sits, from the top of the screen.
    readonly property real screenY: compactLayout ? Math.round(Constants.screenHeight * (crowded ? 0.04 : 0.14)) : tallLayout ? Math.round(Constants.screenHeight * (crowded ? 0.06 : 0.1)) : Math.round((mediaActive ? 170 : 190) * Constants.scaleFactor)
    readonly property real dateSize: mediaActive ? Silica.Theme.fontSizeMedium : tallLayout ? Silica.Theme.fontSizeExtraLarge : Silica.Theme.fontSizeLarge
    // Re-read when the date string turns over at midnight.
    readonly property date today: SystemStatusStore.dateString ? new Date() : new Date()

    implicitHeight: column.height

    // The time and the date below it each take the tone of their own
    // backdrop: a clock over sky can sit above a date over land.
    WallpaperTone {
        id: clockTone

        objectName: "lockClockTone"
        y: -column.spacing
        width: root.width
        height: clock.height + Math.round(1.5 * column.spacing)
    }

    WallpaperTone {
        id: dateTone

        objectName: "lockDateTone"
        y: clock.height + Math.round(column.spacing / 2)
        width: root.width
        height: column.height - clock.height + Math.round(column.spacing / 2)
    }

    Column {
        id: column

        width: root.width
        spacing: Constants.spacingSmall

        Silica.Label {
            id: clock

            readonly property int clockSize: Math.round(Silica.Theme.fontSizeHuge * (root.tallLayout ? (root.mediaActive ? 2.6 : 3.2) : (root.mediaActive ? 1.6 : 1.9)))

            objectName: "lockClock"
            text: SystemStatusStore.timeString
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            font.pixelSize: clockSize
            font.weight: Font.ExtraLight
            // Display sizes set tighter; figures of one width, so the clock never shifts.
            font.letterSpacing: -0.02 * clockSize
            font.features: ({
                    "tnum": 1
                })
            color: clockTone.glyph
            style: Text.Outline
            styleColor: clockTone.halo
        }

        // The weekday shares its row with the weather; with media below,
        // the date joins them, so the clock never takes more than two lines.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Silica.Theme.paddingLarge

            Silica.Label {
                objectName: "lockDay"
                //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Day and month for the lock screen date, e.g. 26 October
                readonly property string date: Qt.formatDate(root.today, qsTr("d MMMM"))
                //: Weekday and date on one line on the lock screen, e.g. Monday, 26 October
                text: root.mediaActive ? qsTr("%1, %2").arg(Qt.formatDate(root.today, "dddd")).arg(date) : Qt.formatDate(root.today, "dddd")
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: root.dateSize
                color: dateTone.glyph
                style: Text.Outline
                styleColor: dateTone.halo
            }
            Row {
                id: weather

                readonly property var current: WeatherClient.forecast.current || null

                objectName: "lockWeather"
                spacing: Silica.Theme.paddingSmall
                visible: current !== null
                anchors.verticalCenter: parent.verticalCenter

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: weather.current ? Weather.glyph(weather.current.symbol, ((WeatherClient.forecast.hourly || [])[0] || {}).is_day) : ""
                    size: Silica.Theme.iconSizeSmall
                    color: dateTone.glyph
                }
                Silica.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: weather.current ? Weather.temperature(weather.current.temperature, SettingsManagerCpp.fahrenheit) : ""
                    font.pixelSize: root.dateSize
                    color: dateTone.glyph
                    style: Text.Outline
                    styleColor: dateTone.halo
                }
            }
        }
        Silica.Label {
            objectName: "lockDate"
            visible: !root.mediaActive
            text: Qt.formatDate(root.today, qsTr("d MMMM"))
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.dateSize
            color: dateTone.glyph
            style: Text.Outline
            styleColor: dateTone.halo
        }
    }
}
