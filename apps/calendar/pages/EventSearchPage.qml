pragma ComponentBehavior: Bound
import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    property var events: []
    readonly property string query: searchField.text.trim().toLowerCase()
    readonly property var results: {
        if (query === "")
            return [];
        return events.filter(e => String(e.title || "").toLowerCase().indexOf(query) !== -1).sort((a, b) => String(a.date + a.time).localeCompare(String(b.date + b.time)));
    }

    signal eventChosen(var event)

    color: MColors.background
    Component.onCompleted: searchField.focusInput()

    MSearchField {
        id: searchField

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        placeholder: "Search events"
    }

    ListView {
        id: resultsList

        anchors.top: searchField.bottom
        anchors.topMargin: MSpacing.sm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.results

        delegate: EventListItem {
            required property var modelData

            width: resultsList.width
            title: modelData.title
            time: Qt.formatDate(Date.fromLocaleString(Qt.locale(), modelData.date, "yyyy-MM-dd"), "ddd, MMM d, yyyy") + (modelData.allDay ? " · All Day" : " · " + modelData.time)
            date: modelData.date
            onClicked: root.eventChosen(modelData)
        }
    }

    MEmptyState {
        anchors.centerIn: resultsList
        width: parent.width - MSpacing.xl * 2
        visible: resultsList.count === 0
        iconName: "magnifying-glass"
        iconSize: 64
        title: root.query === "" ? "Search your events" : "No matching events"
        message: root.query === "" ? "Type part of an event's title." : "Try a different word."
    }
}
