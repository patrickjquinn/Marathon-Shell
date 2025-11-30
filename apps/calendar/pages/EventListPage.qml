import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme

Page {
    background: Rectangle {
        color: MColors.background
    }

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
                title: "Upcoming Events"
                subtitle: calendarApp.events.length === 0 ? "No events scheduled. Tap + to create one." : calendarApp.events.length + " event" + (calendarApp.events.length === 1 ? "" : "s")
                width: parent.width - 48

                Repeater {
                    model: calendarApp.events

                    MSettingsListItem {
                        title: modelData.title
                        subtitle: modelData.allDay ? Qt.formatDate(new Date(modelData.date), "MMMM d, yyyy") : Qt.formatDate(new Date(modelData.date), "MMM d") + " at " + modelData.time
                        iconName: "calendar"
                        showChevron: true
                        onSettingClicked: {
                            console.log("View event:", modelData.title);
                        }
                    }
                }
            }

            Item {
                height: 80
            }
        }
    }
}
