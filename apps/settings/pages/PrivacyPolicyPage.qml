import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: privacyPage

    property string pageName: "privacy"

    pageTitle: "Privacy Policy"

    content: Flickable {
        contentHeight: privacyContent.height + 40
        clip: true

        Column {
            id: privacyContent

            width: parent.width
            spacing: MSpacing.lg
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Data on Device"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "Marathon OS stores settings and app data locally on your device. We do not collect personal data by default."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            MSection {
                title: "Permissions"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "Apps request permissions for access to features such as network, storage, or location. You can change permissions per app in Settings."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            MSection {
                title: "Diagnostics"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "Diagnostic logs are stored locally and can be shared by you for support or debugging."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
