pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
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
                title: qsTr("Trackpad")
            }
            Repeater {
                model: Logic.trackpadModes

                TextSwitch {
                    required property var modelData

                    objectName: "trackpadMode-" + modelData.id
                    automaticCheck: false
                    checked: Settings.trackpadMode === modelData.id
                    text: modelData.title
                    description: modelData.description
                    onClicked: Settings.trackpadMode = modelData.id
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
