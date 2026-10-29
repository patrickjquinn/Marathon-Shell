pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

TabItem {
    id: root

    property var app
    property real topMargin
    property date now: new Date()

    flickable: list

    Timer {
        interval: 60000 - root.now.getSeconds() * 1000 - root.now.getMilliseconds()
        repeat: true
        triggeredOnStart: true
        running: root.isCurrentItem && Application.state === Qt.ApplicationActive
        onTriggered: root.now = new Date()
    }

    SilicaListView {
        id: list

        objectName: "alarmList"
        anchors.fill: parent
        model: root.app.alarms
        header: Column {
            width: list.width
            topPadding: root.topMargin + Theme.paddingLarge * 2
            bottomPadding: Theme.paddingLarge

            Label {
                objectName: "alarmsClock"
                anchors.horizontalCenter: parent.horizontalCenter
                text: Format.formatDate(root.now, Formatter.TimeValue)
                font.pixelSize: Theme.fontSizeHuge
                font.features: ({
                        "tnum": 1
                    })
                color: Theme.highlightColor
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Format.formatDate(root.now, Formatter.DateLong)
                color: Theme.secondaryHighlightColor
            }
        }

        PullDownMenu {
            MenuItem {
                objectName: "newAlarm"
                text: qsTr("New alarm")
                onClicked: root.app.editAlarm(null)
            }
        }

        ViewPlaceholder {
            objectName: "alarmsPlaceholder"
            enabled: list.count === 0
            text: qsTr("No alarms")
            hintText: qsTr("Pull down to add one")
            verticalOffset: Math.max(0, (list.headerItem ? list.headerItem.height : 0) + Theme.paddingLarge - (list.height / 3 - height / 2))
        }

        delegate: AlarmDelegate {
            app: root.app
        }

        VerticalScrollDecorator {}
    }
}
