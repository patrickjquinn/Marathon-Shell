pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property bool silent: Settings.privacySwitch === "silent"

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Privacy switch")
            }
            Repeater {
                model: Logic.privacySwitchModes

                TextSwitch {
                    required property var modelData

                    objectName: "privacySwitchMode-" + modelData.id
                    automaticCheck: false
                    checked: page.silent === (modelData.id === "silent")
                    text: modelData.title
                    description: modelData.description
                    onClicked: {
                        if (!checked)
                            Settings.privacySwitch = modelData.id === "silent" ? "silent" : "microphone,camera,location";
                    }
                }
            }
            SectionHeader {
                visible: !page.silent
                text: qsTr("With the switch on")
            }
            Repeater {
                model: page.silent ? [] : Logic.privacySwitchCuts

                TextSwitch {
                    required property var modelData

                    objectName: "privacySwitchCut-" + modelData.id
                    automaticCheck: false
                    checked: Logic.privacySwitchCovers(Settings.privacySwitch).includes(modelData.id)
                    text: modelData.title
                    onClicked: Settings.privacySwitch = Logic.privacySwitchToggled(Settings.privacySwitch, modelData.id)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
