pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app

    SilicaListView {
        id: view

        objectName: "categoryView"
        anchors.fill: parent
        header: PageHeader {
            title: qsTr("Service tests")
            description: page.app.summary
        }
        model: ListModel {
            Component.onCompleted: {
                append({
                    title: qsTr("Telephony & SMS"),
                    icon: "phone",
                    file: "TelephonyTestsPage.qml"
                });
                append({
                    title: qsTr("Notifications"),
                    icon: "events",
                    file: "NotificationTestsPage.qml"
                });
                append({
                    title: qsTr("Alarms & wake"),
                    icon: "alarm",
                    file: "AlarmTestsPage.qml"
                });
                append({
                    title: qsTr("Media & audio"),
                    icon: "music",
                    file: "MediaTestsPage.qml"
                });
                append({
                    title: qsTr("System services"),
                    icon: "developer-mode",
                    file: "SystemTestsPage.qml"
                });
                append({
                    title: qsTr("Sensors & location"),
                    icon: "gps",
                    file: "SensorTestsPage.qml"
                });
            }
        }

        delegate: ListItem {
            id: item

            required property string title
            required property string icon
            required property string file

            Accessible.name: title
            onClicked: pageStack.push(Qt.resolvedUrl(item.file), {
                app: page.app
            })

            Icon {
                id: glyph

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-" + item.icon
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                anchors {
                    left: glyph.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: item.title
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
