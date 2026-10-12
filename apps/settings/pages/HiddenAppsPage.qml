pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    SilicaListView {
        id: view

        objectName: "appList"
        anchors.fill: parent
        model: Apps
        header: PageHeader {
            title: qsTr("Hidden apps")
            description: qsTr("Kept installed, left off the app grid")
        }

        delegate: TextSwitch {
            required property var model

            objectName: "hide-" + model.id
            text: model.name
            automaticCheck: false
            checked: Settings.hiddenApps.indexOf(model.id) >= 0
            onClicked: Settings.hiddenApps = Logic.setMember(Settings.hiddenApps, model.id, !checked)
        }

        VerticalScrollDecorator {}
    }
}
