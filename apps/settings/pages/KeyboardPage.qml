import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Page {
    id: keyboardPage

    property string pageName: "keyboard"
    signal navigateBack

    Component.onCompleted: {
        Logger.info("KeyboardPage", "Initialized");
    }

    Flickable {
        id: scrollView

        anchors.fill: parent
        contentHeight: keyboardContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 1500
        maximumFlickVelocity: 2500

        Column {
            id: keyboardContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            Row {
                spacing: MSpacing.md
                width: parent.width - 48

                MIconButton {
                    iconName: "chevron-left"
                    iconSize: 24
                    onClicked: keyboardPage.navigateBack()
                }

                Text {
                    text: "Keyboard"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MSection {
                title: "Language"
                subtitle: "Select your keyboard language"
                width: parent.width - 48

                Repeater {
                    model: KeyboardSettingsStore.availableLanguages

                    MSettingsListItem {
                        title: KeyboardSettingsStore.getLanguageName(modelData)
                        subtitle: modelData
                        iconName: KeyboardSettingsStore.currentLanguage === modelData ? "check" : ""
                        showChevron: false
                        onSettingClicked: {
                            KeyboardSettingsStore.currentLanguage = modelData;
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: 16
                            color: KeyboardSettingsStore.currentLanguage === modelData ? MColors.accentBright : "transparent"
                            visible: KeyboardSettingsStore.currentLanguage === modelData

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: MColors.bb10Black
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }
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
                height: 40
            }
        }
    }

    background: Rectangle {
        color: MColors.background
    }
}
