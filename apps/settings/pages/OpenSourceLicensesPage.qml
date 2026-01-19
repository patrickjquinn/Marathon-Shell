import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: licensesPage

    property string pageName: "licenses"

    pageTitle: "Open Source Licenses"

    content: Flickable {
        contentHeight: licensesContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: licensesContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            Text {
                text: "Marathon OS ships with open source components. Licenses below reflect the components used in this build."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                wrapMode: Text.WordWrap
                width: parent.width - MSpacing.lg * 2
            }

            Repeater {
                model: SettingsController.openSourceLicenses

                MSection {
                    required property var modelData
                    title: modelData.title
                    width: parent.width - MSpacing.lg * 2

                    Column {
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: modelData.items

                            MSettingsListItem {
                                required property var modelData
                                title: modelData.title
                                subtitle: modelData.subtitle
                                value: modelData.value
                            }
                        }
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
