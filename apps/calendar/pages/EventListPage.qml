import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Page {
    property int updateTrigger: 0

    MScrollView {
        id: scrollView

        anchors.fill: parent
        contentHeight: calendarContent.height + 40

        Column {
            id: calendarContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            Text {
                text: "Calendar"
                color: MColors.text
                font.pixelSize: MTypography.sizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }

            MSection {
                title: calendarApp.selectedDate ? Qt.formatDate(calendarApp.selectedDate, "MMMM d, yyyy") : "Upcoming Events"
                subtitle: {
                    var count = eventListRepeater.count;
                    if (count === 0)
                        return "No events scheduled.";

                    return count + " event" + (count === 1 ? "" : "s");
                }
                width: parent.width - 48

                MButton {
                    visible: calendarApp.selectedDate !== null
                    text: "Show All Events"
                    variant: "secondary"
                    width: parent.width
                    onClicked: calendarApp.selectedDate = null
                }

                Repeater {
                    id: eventListRepeater

                    model: {
                        var _ = updateTrigger;
                        if (calendarApp.selectedDate)
                            return calendarApp.getEventsForDate(calendarApp.selectedDate);

                        return calendarApp.getAllEvents();
                    }

                    EventListItem {
                        title: modelData.title
                        time: modelData.time
                        date: modelData.date
                        allDay: modelData.allDay
                        onClicked: {
                            calendarApp.openEventDetail(modelData);
                        }
                    }
                }
            }

            Connections {
                function onDataChanged() {
                    updateTrigger++;
                }

                target: calendarApp
            }

            Item {
                height: 80
            }
        }
    }

    background: Rectangle {
        color: MColors.background
    }
}
