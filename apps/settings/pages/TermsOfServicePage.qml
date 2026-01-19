import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: tosPage

    property string pageName: "tos"

    pageTitle: "Terms of Service"

    content: Flickable {
        contentHeight: tosContent.height + 40
        clip: true

        Column {
            id: tosContent

            width: parent.width
            spacing: MSpacing.lg
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Agreement"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "By using Marathon OS, you agree to use the system responsibly and lawfully. You are responsible for the content you create or access on this device."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            MSection {
                title: "Warranty"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "Marathon OS is provided \"as is\" without warranties of any kind. We do not guarantee uninterrupted operation or compatibility with all hardware."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            MSection {
                title: "Updates"
                width: parent.width - 48

                Text {
                    width: parent.width
                    text: "System updates may change features or behavior. You may choose whether to install optional updates."
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
