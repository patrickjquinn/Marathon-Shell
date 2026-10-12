import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

TabItem {
    id: root

    property var app
    property real topMargin

    flickable: list

    SilicaListView {
        id: list

        objectName: "alarmList"
        anchors.fill: parent
        model: root.app.alarms
        header: Item {
            width: 1
            height: root.topMargin
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
        }

        delegate: AlarmDelegate {
            app: root.app
        }

        VerticalScrollDecorator {}
    }
}
