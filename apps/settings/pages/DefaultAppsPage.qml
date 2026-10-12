pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Default apps")
            }
            Repeater {
                model: Logic.handlers

                Column {
                    id: handler

                    required property var modelData
                    required property int index

                    width: column.width

                    SectionHeader {
                        text: handler.modelData.section
                        visible: handler.index === 0 || Logic.handlers[handler.index - 1].section !== handler.modelData.section
                    }
                    ValueButton {
                        objectName: "handler-" + handler.modelData.id
                        label: handler.modelData.title
                        value: SettingsController.defaultAppName(handler.modelData.id, SettingsController.defaultAppsRevision)
                        onClicked: pageStack.push(Qt.resolvedUrl("AppPickerPage.qml"), { handler: handler.modelData.id, title: handler.modelData.title })
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
