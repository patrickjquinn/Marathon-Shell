pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    function resetTiles() {
        Settings.enabledQuickSettingsTiles = Logic.defaultTiles;
    }

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: view

        objectName: "tileList"
        anchors.fill: parent
        model: Logic.tiles
        header: PageHeader {
            title: qsTr("Quick settings")
            description: qsTr("Tiles shown in the top menu")
        }

        PullDownMenu {
            MenuItem {
                objectName: "resetItem"
                text: qsTr("Reset to defaults")
                onClicked: remorse.execute(qsTr("Resetting tiles"), page.resetTiles)
            }
        }

        delegate: TextSwitch {
            required property var modelData

            objectName: "tile-" + modelData.id
            text: modelData.label
            description: modelData.desc
            automaticCheck: false
            checked: Settings.enabledQuickSettingsTiles.indexOf(modelData.id) >= 0
            onClicked: Settings.enabledQuickSettingsTiles = Logic.setMember(Settings.enabledQuickSettingsTiles, modelData.id, !checked)
        }

        VerticalScrollDecorator {}
    }
}
