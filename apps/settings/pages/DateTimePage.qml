import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    property date now: new Date()

    Timer {
        interval: 30000
        repeat: true
        running: page.status === PageStatus.Active
        onTriggered: page.now = new Date()
    }

    TimeZoneList {
        id: zones
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Date and time")
            }
            TextSwitch {
                objectName: "clockSwitch"
                text: qsTr("24-hour clock")
                description: Qt.formatTime(page.now, Settings.timeFormat === "24h" ? "HH:mm" : "h:mm AP")
                automaticCheck: false
                checked: Settings.timeFormat === "24h"
                onClicked: Settings.timeFormat = checked ? "12h" : "24h"
            }
            ValueButton {
                objectName: "zoneButton"
                label: qsTr("Time zone")
                value: zones.displayName(Settings.timeZone || "UTC")
                onClicked: pageStack.push(Qt.resolvedUrl("TimeZonePage.qml"))
            }
        }

        VerticalScrollDecorator {}
    }
}
