import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app
    property var eventId
    readonly property var event: app.eventById(eventId)
    // Kept so the page still reads right while it pops after a delete.
    property var shown: ({})

    onEventChanged: {
        if (event)
            shown = event;
    }
    Component.onCompleted: {
        if (event)
            shown = event;
    }

    function remove() {
        const id = eventId;
        remorse.execute(qsTr("Deleted %1").arg(shown.title), function () {
            if (page.app.deleteEvent(id))
                pageStack.pop();
        });
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
    }

    SilicaFlickable {
        objectName: "eventView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "deleteItem"
                text: qsTr("Delete")
                enabled: page.event !== null
                onClicked: page.remove()
            }
            MenuItem {
                objectName: "editItem"
                text: qsTr("Edit")
                enabled: page.event !== null
                onClicked: page.app.editEvent(page.event)
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                objectName: "eventHeader"
                title: page.shown.title || qsTr("Untitled event")
                wrapMode: Text.Wrap
            }
            DetailItem {
                objectName: "dateDetail"
                label: qsTr("Date")
                value: page.shown.date ? page.app.dateText(page.shown) : ""
            }
            DetailItem {
                objectName: "timeDetail"
                label: qsTr("Time")
                value: page.shown.date ? page.app.timeRangeText(page.shown) : ""
            }
            DetailItem {
                objectName: "locationDetail"
                label: qsTr("Location")
                visible: !!page.shown.location
                value: page.shown.location || ""
            }
            DetailItem {
                objectName: "repeatDetail"
                label: qsTr("Repeats")
                visible: !!page.shown.recurring && page.shown.recurring !== "none"
                value: page.app.repeatText(page.shown.recurring)
            }
            DetailItem {
                objectName: "reminderDetail"
                label: qsTr("Reminder")
                value: page.app.reminderText(page.shown.reminder === undefined ? 0 : page.shown.reminder)
            }

            SectionHeader {
                visible: descriptionLabel.text !== ""
                text: qsTr("Description")
            }
            Label {
                id: descriptionLabel

                objectName: "description"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text !== ""
                text: page.shown.description || ""
                wrapMode: Text.Wrap
                color: Theme.highlightColor
            }
        }

        VerticalScrollDecorator {}
    }
}
