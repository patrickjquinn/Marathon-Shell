import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonUI.Core
import "../components"
import "../stores"

Page {
    background: Rectangle {
        color: MColors.background
    }

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
                    if (count === 0) return "No events scheduled.";
                    return count + " event" + (count === 1 ? "" : "s");
                }
                width: parent.width - 48

                // Clear selection button
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
                        // Dependency on dataChanged signal
                        var _ = updateTrigger; 
                        
                        if (calendarApp.selectedDate) {
                            return CalendarStorage.getEventsForDate(calendarApp.selectedDate);
                        }
                        return CalendarStorage.events;
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
                target: CalendarStorage
                function onDataChanged() {
                    updateTrigger++;
                }
            }



            Item {
                height: 80
            }
        }
    }
}
