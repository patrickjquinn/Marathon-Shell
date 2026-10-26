pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import "../core/Clock.js" as Clock
import "../core/Weather.js" as Weather

// The Hub's weather: now, and the coming hours under the caret.
Column {
    id: card

    readonly property var forecast: WeatherClient.forecast
    readonly property var current: forecast.current || null
    readonly property var today: (forecast.daily || [])[0] || null
    readonly property bool twelveHour: Clock.twelveHour(SettingsManagerCpp.timeFormat)
    property bool expanded: String(SettingsManagerCpp.get("weather/expanded", false)) === "true"
    // Until the service answers, skeletons hold the card's place so nothing
    // below it moves when the weather arrives.
    readonly property bool loading: current === null && !gaveUp && (WeatherClient.state === "" || WeatherClient.state === "updating")
    property bool gaveUp: false
    property real detailsHeight: Number(SettingsManagerCpp.get("weather/detailsHeight", Silica.Theme.itemSizeHuge * 2))

    component Skeleton: Rectangle {
        radius: height / 2
        color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.12)
    }

    signal openRequested

    // Without the service there is nothing to say.
    visible: current !== null || WeatherClient.state === "no-location" || loading
    spacing: Silica.Theme.paddingSmall

    Timer {
        interval: 5000
        running: WeatherClient.state === "" && card.current === null
        onTriggered: card.gaveUp = true
    }

    SequentialAnimation {
        running: MMotion.gate(card.loading && card.visible)
        loops: Animation.Infinite
        onRunningChanged: if (!running)
            card.pulse = 1

        NumberAnimation {
            target: card
            property: "pulse"
            to: 0.45
            duration: 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: card
            property: "pulse"
            to: 1
            duration: 700
            easing.type: Easing.InOutSine
        }
    }
    property real pulse: 1

    Item {
        width: parent.width
        height: Silica.Theme.itemSizeLarge

        Silica.BackgroundItem {
            id: summary

            objectName: "weatherSummary"
            anchors.left: parent.left
            anchors.right: caret.visible ? caret.left : parent.right
            height: parent.height
            onClicked: card.openRequested()

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Silica.Theme.paddingLarge
                visible: card.loading
                opacity: card.pulse

                Skeleton {
                    width: Silica.Theme.iconSizeLarge
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Silica.Theme.paddingSmall

                    Skeleton {
                        width: Silica.Theme.itemSizeHuge * 1.6
                        height: Silica.Theme.fontSizeSmall
                    }
                    Skeleton {
                        width: Silica.Theme.itemSizeHuge
                        height: Silica.Theme.fontSizeExtraSmall
                    }
                }
            }

            GlyphIcon {
                id: sky

                visible: !card.loading

                anchors.verticalCenter: parent.verticalCenter
                name: card.current ? Weather.glyph(card.current.symbol, ((card.forecast.hourly || [])[0] || {}).is_day) : "cloud"
                size: Silica.Theme.iconSizeLarge
                color: Silica.Theme.primaryColor
            }
            Silica.Label {
                id: temperature

                anchors.left: sky.right
                anchors.leftMargin: Silica.Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                visible: card.current !== null
                text: card.current ? Weather.temperature(card.current.temperature, WeatherClient.fahrenheit) : ""
                font.pixelSize: Silica.Theme.fontSizeExtraLarge
                font.family: Silica.Theme.fontFamilyHeading
                font.weight: Font.Light
            }
            Column {
                anchors.left: temperature.visible ? temperature.right : sky.right
                anchors.leftMargin: Silica.Theme.paddingLarge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !card.loading

                Silica.Label {
                    width: parent.width
                    truncationMode: Silica.TruncationMode.Fade
                    text: card.current ? (card.forecast.location || {}).name || "" : qsTr("Weather")
                }
                Silica.Label {
                    width: parent.width
                    truncationMode: Silica.TruncationMode.Fade
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    color: Silica.Theme.secondaryColor
                    text: {
                        if (!card.current)
                            return WeatherClient.state === "no-location" ? qsTr("Choose a place to see its weather") : "";
                        const parts = [Weather.condition(card.current.symbol)];
                        if (card.today)
                            parts.push(qsTr("H %1 L %2").arg(Weather.temperature(card.today.high, WeatherClient.fahrenheit)).arg(Weather.temperature(card.today.low, WeatherClient.fahrenheit)));
                        return parts.filter(p => p).join(" · ");
                    }
                }
            }
        }

        Silica.BackgroundItem {
            id: caret

            objectName: "weatherCaret"
            width: Silica.Theme.itemSizeSmall
            height: width
            anchors.right: parent.right
            anchors.rightMargin: -Silica.Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            visible: card.current !== null
            onClicked: {
                card.expanded = !card.expanded;
                SettingsManagerCpp.set("weather/expanded", card.expanded);
            }

            GlyphIcon {
                anchors.centerIn: parent
                name: "caret-down"
                size: Silica.Theme.iconSizeSmallPlus
                color: caret.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                rotation: card.expanded ? 180 : 0

                Behavior on rotation {
                    NumberAnimation {
                        duration: MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: !card.expanded ? 0 : card.current ? details.implicitHeight : card.loading ? card.detailsHeight : 0
        clip: true
        visible: height > 0

        Column {
            width: parent.width
            spacing: Silica.Theme.paddingMedium
            visible: card.loading
            opacity: card.pulse

            Skeleton {
                width: parent.width * 0.7
                height: Silica.Theme.fontSizeExtraSmall
            }
            Skeleton {
                width: parent.width
                height: card.detailsHeight - Silica.Theme.fontSizeExtraSmall - Silica.Theme.paddingMedium * 2
                radius: Silica.Theme.paddingSmall
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            anchors.fill: details
            onClicked: card.openRequested()
        }

        Column {
            id: details

            width: parent.width
            spacing: Silica.Theme.paddingMedium
            visible: card.current !== null
            onImplicitHeightChanged: if (card.current && implicitHeight > 0 && Math.abs(implicitHeight - card.detailsHeight) > 1) {
                card.detailsHeight = implicitHeight;
                SettingsManagerCpp.set("weather/detailsHeight", implicitHeight);
            }

            Silica.Label {
                width: parent.width
                wrapMode: Text.Wrap
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                color: Silica.Theme.secondaryHighlightColor
                text: Weather.outlook(card.forecast.hourly, Date.now() / 1000, card.forecast.timezone_offset, card.twelveHour)
            }
            WeatherHourlyChart {
                objectName: "hubHourlyChart"
                width: parent.width
                height: implicitHeight
                hours: Weather.upcoming(card.forecast.hourly, Date.now() / 1000, 6, 3)
                offset: card.forecast.timezone_offset || 0
                fahrenheit: WeatherClient.fahrenheit
                twelveHour: card.twelveHour
            }
        }
    }
}
