import MarathonApp.Settings
import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

SettingsPageTemplate {
    id: appSortPage

    property string pageName: "appsort"

    pageTitle: "App Sorting & Layout"

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

            MSection {
                title: "Sort Order"
                subtitle: "Choose how apps are organized"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Alphabetical"
                    subtitle: "Sort by name A-Z"
                    value: (SettingsManagerCpp.appSortOrder === "alphabetical") ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "alphabetical";
                        Logger.info("AppSort", "Sort order: alphabetical");
                    }
                }

                MSettingsListItem {
                    title: "Most Used"
                    subtitle: "Frequently opened apps first"
                    value: (SettingsManagerCpp.appSortOrder === "frequent") ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "frequent";
                        Logger.info("AppSort", "Sort order: frequent");
                    }
                }

                MSettingsListItem {
                    title: "Recently Added"
                    subtitle: "Newest apps first"
                    value: (SettingsManagerCpp.appSortOrder === "recent") ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "recent";
                        Logger.info("AppSort", "Sort order: recent");
                    }
                }

                MSettingsListItem {
                    title: "Custom"
                    subtitle: "Manual arrangement"
                    value: (SettingsManagerCpp.appSortOrder === "custom") ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "custom";
                        Logger.info("AppSort", "Sort order: custom");
                    }
                }
            }

            MSection {
                title: "Grid Layout"
                subtitle: "Number of app columns"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Auto"
                    subtitle: "Responsive based on screen size"
                    value: (SettingsManagerCpp.appGridColumns === 0) ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 0;
                        Logger.info("AppSort", "Grid columns: auto");
                    }
                }

                MSettingsListItem {
                    title: "3 Columns"
                    subtitle: "Larger icons"
                    value: (SettingsManagerCpp.appGridColumns === 3) ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 3;
                        Logger.info("AppSort", "Grid columns: 3");
                    }
                }

                MSettingsListItem {
                    title: "4 Columns"
                    subtitle: "Balanced layout"
                    value: (SettingsManagerCpp.appGridColumns === 4) ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 4;
                        Logger.info("AppSort", "Grid columns: 4");
                    }
                }

                MSettingsListItem {
                    title: "5 Columns"
                    subtitle: "Compact view"
                    value: (SettingsManagerCpp.appGridColumns === 5) ? "✓" : ""
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 5;
                        Logger.info("AppSort", "Grid columns: 5");
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
