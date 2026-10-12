pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Keyboard")
            }
            ComboBox {
                objectName: "languageCombo"
                width: parent.width
                label: qsTr("Language")
                Binding on currentIndex {
                    value: KeyboardSettingsStore.availableLanguages.indexOf(KeyboardSettingsStore.currentLanguage)
                }
                menu: ContextMenu {
                    Repeater {
                        model: KeyboardSettingsStore.availableLanguages

                        MenuItem {
                            required property string modelData

                            text: KeyboardSettingsStore.getLanguageName(modelData)
                            onClicked: KeyboardSettingsStore.currentLanguage = modelData
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Typing")
            }
            TextSwitch {
                objectName: "autoCorrectSwitch"
                text: qsTr("Auto-correct")
                description: qsTr("Corrects misspelled words")
                automaticCheck: false
                checked: KeyboardSettingsStore.autoCorrectEnabled
                onClicked: KeyboardSettingsStore.autoCorrectEnabled = !checked
            }
            TextSwitch {
                objectName: "autoCapitalizeSwitch"
                text: qsTr("Auto-capitalize")
                description: qsTr("Capitalizes the first letter of sentences")
                automaticCheck: false
                checked: KeyboardSettingsStore.autoCapitalizeEnabled
                onClicked: KeyboardSettingsStore.autoCapitalizeEnabled = !checked
            }
            TextSwitch {
                objectName: "predictionsSwitch"
                text: qsTr("Word predictions")
                description: qsTr("Suggests words while you type")
                automaticCheck: false
                checked: KeyboardSettingsStore.predictionsEnabled
                onClicked: KeyboardSettingsStore.predictionsEnabled = !checked
            }
            TextSwitch {
                objectName: "hapticSwitch"
                text: qsTr("Vibrate on key press")
                automaticCheck: false
                checked: KeyboardSettingsStore.hapticFeedbackEnabled
                onClicked: KeyboardSettingsStore.hapticFeedbackEnabled = !checked
            }
        }

        VerticalScrollDecorator {}
    }
}
