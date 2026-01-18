import MarathonApp.Settings
import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

SettingsPageTemplate {
    id: hiddenAppsPage

    property string pageName: "hiddenapps"

    pageTitle: "Hidden Apps"

    content: Flickable {
        contentHeight: contentColumn.height + 40
        clip: true

        Column {
            id: contentColumn

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MLabel {
                text: "Hidden apps won't appear in the app drawer"
                variant: "body"
                color: MColors.textSecondary
                width: parent.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                wrapMode: Text.WordWrap
            }

            MSection {
                title: "All Apps"
                subtitle: SettingsManagerCpp.hiddenApps.length + " hidden"
                width: parent.width - 48

                Repeater {
                    model: AppModel

                    MSettingsListItem {
                        title: model.name
                        subtitle: model.id
                        iconName: ""
                        showToggle: true
                        toggleValue: SettingsManagerCpp.hiddenApps.indexOf(model.id) >= 0
                        onToggleChanged: value => {
                            var hiddenList = SettingsManagerCpp.hiddenApps;
                            var index = hiddenList.indexOf(model.id);
                            if (value && index < 0) {
                                hiddenList.push(model.id);
                                SettingsManagerCpp.hiddenApps = hiddenList;
                                Logger.info("HiddenApps", "Hidden: " + model.id);
                            } else if (!value && index >= 0) {
                                hiddenList.splice(index, 1);
                                SettingsManagerCpp.hiddenApps = hiddenList;
                                Logger.info("HiddenApps", "Unhidden: " + model.id);
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
