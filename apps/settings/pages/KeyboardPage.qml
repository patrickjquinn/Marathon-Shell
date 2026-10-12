pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: keyboardPage

    property string pageName: "keyboard"

    pageTitle: "Keyboard"
    Component.onCompleted: {
        Logger.info("KeyboardPage", "Initialized");
    }

    content: Flickable {
        contentHeight: keyboardContent.height + MSpacing.xxl
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: keyboardContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            MSection {
                title: "Language"
                subtitle: "Select your keyboard language"
                width: parent.width - 48

                Repeater {
                    model: KeyboardSettingsStore.availableLanguages

                    MSettingsListItem {
                        required property var modelData
                        title: KeyboardSettingsStore.getLanguageName(modelData)
                        subtitle: modelData
                        value: KeyboardSettingsStore.currentLanguage === modelData ? "selected" : ""
                        onSettingClicked: {
                            KeyboardSettingsStore.currentLanguage = modelData;
                        }
                    }
                }
            }

            MSection {
                title: "Input Options"
                subtitle: "Customize typing behavior"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Auto-Correct"
                    subtitle: "Automatically correct misspelled words"
                    iconName: "spell-check"
                    showToggle: true
                    toggleValue: KeyboardSettingsStore.autoCorrectEnabled
                    onToggleChanged: value => {
                        KeyboardSettingsStore.autoCorrectEnabled = value;
                    }
                }

                MSettingsListItem {
                    title: "Auto-Capitalize"
                    subtitle: "Capitalize first letter of sentences"
                    iconName: "arrow-up"
                    showToggle: true
                    toggleValue: KeyboardSettingsStore.autoCapitalizeEnabled
                    onToggleChanged: value => {
                        KeyboardSettingsStore.autoCapitalizeEnabled = value;
                    }
                }

                MSettingsListItem {
                    title: "Haptic Feedback"
                    subtitle: "Vibrate on key press"
                    iconName: "vibrate"
                    showToggle: true
                    toggleValue: KeyboardSettingsStore.hapticFeedbackEnabled
                    onToggleChanged: value => {
                        KeyboardSettingsStore.hapticFeedbackEnabled = value;
                    }
                }

                MSettingsListItem {
                    title: "Word Predictions"
                    subtitle: "Show word suggestions while typing"
                    iconName: "message-square"
                    showToggle: true
                    toggleValue: KeyboardSettingsStore.predictionsEnabled
                    onToggleChanged: value => {
                        KeyboardSettingsStore.predictionsEnabled = value;
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
