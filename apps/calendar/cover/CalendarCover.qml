pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import "../CalendarLogic.js" as Logic

CoverBackground {
    id: cover

    property var events: []
    property date now: new Date()
    readonly property var next: Logic.upcoming(events, now)

    signal newEventRequested

    function timeText(event) {
        if (event.allDay)
            return qsTr("All day");
        const t = Logic.parseTime(event.time);
        return Format.formatDate(new Date(2000, 0, 1, t.hour, t.minute), Formatter.TimeValue);
    }

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: cover.status === Cover.Active
        onTriggered: cover.now = new Date()
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Row {
            spacing: Theme.paddingMedium

            Label {
                id: dayLabel

                objectName: "coverDay"
                text: cover.now.getDate()
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraLarge
                font.weight: Font.Light
            }
            Column {
                anchors.verticalCenter: dayLabel.verticalCenter

                Label {
                    text: Qt.locale().standaloneDayName(cover.now.getDay(), Locale.ShortFormat)
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    text: Qt.locale().standaloneMonthName(cover.now.getMonth(), Locale.ShortFormat)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }

        Repeater {
            objectName: "coverEvents"
            model: cover.next.slice(0, 2)

            Column {
                id: event

                required property var modelData

                width: parent.width

                Label {
                    objectName: "coverTime"
                    width: parent.width
                    text: cover.timeText(event.modelData)
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.highlightColor
                }
                Label {
                    objectName: "coverTitle"
                    width: parent.width
                    text: event.modelData.title || qsTr("Untitled event")
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Label {
            objectName: "coverMore"
            width: parent.width
            visible: cover.next.length > 2
            text: qsTr("%1 more today").arg(cover.next.length - 2)
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
        Label {
            objectName: "coverEmpty"
            width: parent.width
            visible: cover.next.length === 0
            text: qsTr("No more events today")
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "newEventAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.newEventRequested()
        }
    }
}
