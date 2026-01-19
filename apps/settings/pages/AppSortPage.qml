pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

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
                    iconName: "arrow-down-up"
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "alphabetical";
                        Logger.info("AppSort", "Sort order: alphabetical");
                    }
                }

                MSettingsListItem {
                    title: "Most Used"
                    subtitle: "Frequently opened apps first"
                    value: (SettingsManagerCpp.appSortOrder === "frequent") ? "✓" : ""
                    iconName: "star"
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "frequent";
                        Logger.info("AppSort", "Sort order: frequent");
                    }
                }

                MSettingsListItem {
                    title: "Recently Added"
                    subtitle: "Newest apps first"
                    value: (SettingsManagerCpp.appSortOrder === "recent") ? "✓" : ""
                    iconName: "clock"
                    onSettingClicked: {
                        SettingsManagerCpp.appSortOrder = "recent";
                        Logger.info("AppSort", "Sort order: recent");
                    }
                }

                MSettingsListItem {
                    title: "Custom"
                    subtitle: "Manual arrangement"
                    value: (SettingsManagerCpp.appSortOrder === "custom") ? "✓" : ""
                    iconName: "move"
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
                    iconName: "layout-grid"
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 0;
                        Logger.info("AppSort", "Grid columns: auto");
                    }
                }

                MSettingsListItem {
                    title: "3 Columns"
                    subtitle: "Larger icons"
                    value: (SettingsManagerCpp.appGridColumns === 3) ? "✓" : ""
                    iconName: "layout-grid"
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 3;
                        Logger.info("AppSort", "Grid columns: 3");
                    }
                }

                MSettingsListItem {
                    title: "4 Columns"
                    subtitle: "Balanced layout"
                    value: (SettingsManagerCpp.appGridColumns === 4) ? "✓" : ""
                    iconName: "layout-grid"
                    onSettingClicked: {
                        SettingsManagerCpp.appGridColumns = 4;
                        Logger.info("AppSort", "Grid columns: 4");
                    }
                }

                MSettingsListItem {
                    title: "5 Columns"
                    subtitle: "Compact view"
                    value: (SettingsManagerCpp.appGridColumns === 5) ? "✓" : ""
                    iconName: "layout-grid"
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
