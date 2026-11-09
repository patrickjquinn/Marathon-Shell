pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0

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
                visible: Haptics.available
                text: qsTr("Vibrate on key press")
                description: Settings.vibrationEnabled ? qsTr("A short buzz for each key") : qsTr("Turn on Vibration in Sounds first")
                enabled: Settings.vibrationEnabled
                automaticCheck: false
                checked: KeyboardSettingsStore.hapticFeedbackEnabled
                onClicked: KeyboardSettingsStore.hapticFeedbackEnabled = !checked
            }

            SectionHeader {
                text: qsTr("Hardware keyboard")
            }
            BackgroundItem {
                objectName: "speedKeysEntry"
                contentHeight: Theme.itemSizeMedium
                Accessible.name: qsTr("Speed keys")
                onClicked: pageStack.push(Qt.resolvedUrl("SpeedKeysPage.qml"))

                Column {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        text: qsTr("Speed keys")
                    }
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: qsTr("Hold a letter on the home screen to open an app")
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
