pragma ComponentBehavior: Bound
import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Page {
    id: root

    required property var app
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
                // Calendar uses the Title-3 + subtitle variant deliberately
                // so the date subhead and "n events" descriptor can both
                // surface — eyebrow mode is for settings-list headers
                // where the subtitle would read as noise.
                eyebrow: false
                title: root.app.selectedDate ? Qt.formatDate(root.app.selectedDate, "MMMM d, yyyy") : "Upcoming Events"
                subtitle: {
                    var count = eventListRepeater.count;
                    if (count === 0)
                        return "No events scheduled.";

                    return count + " event" + (count === 1 ? "" : "s");
                }
                width: parent.width - 48

                MButton {
                    visible: root.app.selectedDate !== null
                    text: "Show All Events"
                    variant: "secondary"
                    width: parent.width
                    onClicked: root.app.selectedDate = null
                }

                Repeater {
                    id: eventListRepeater

                    model: {
                        var _ = root.updateTrigger;
                        if (root.app.selectedDate)
                            return root.app.getEventsForDate(root.app.selectedDate);

                        return root.app.getAllEvents();
                    }

                    EventListItem {
                        required property var modelData

                        title: modelData.title
                        time: modelData.time
                        date: modelData.date
                        allDay: modelData.allDay
                        onClicked: {
                            root.app.openEventDetail(modelData);
                        }
                    }
                }
            }

            Connections {
                function onEventsChanged() {
                    root.updateTrigger++;
                }

                target: root.app
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
