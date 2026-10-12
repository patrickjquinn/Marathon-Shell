pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
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
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Row {
            spacing: Theme.paddingMedium

            Label {
                id: dayLabel

                objectName: "coverDay"
                text: cover.now.getDate()
                font.pixelSize: Theme.fontSizeHuge
            }
            Label {
                anchors.baseline: dayLabel.baseline
                text: Qt.locale().standaloneDayName(cover.now.getDay(), Locale.ShortFormat)
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.secondaryColor
            }
        }

        Label {
            objectName: "coverTitle"
            width: parent.width
            visible: cover.next.length > 0
            text: cover.next.length > 0 ? cover.next[0].title || qsTr("Untitled event") : ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
        }
        Label {
            objectName: "coverTime"
            width: parent.width
            visible: cover.next.length > 0
            text: cover.next.length > 0 ? cover.timeText(cover.next[0]) : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.highlightColor
        }
        Label {
            objectName: "coverMore"
            width: parent.width
            visible: cover.next.length > 1
            text: cover.next.length === 2 ? qsTr("1 more today") : qsTr("%1 more today").arg(cover.next.length - 1)
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
        }

        Label {
            objectName: "coverEmpty"
            width: parent.width
            visible: cover.next.length === 0
            text: qsTr("No more events today")
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeMedium
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
