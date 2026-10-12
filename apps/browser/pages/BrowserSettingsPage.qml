pragma ComponentBehavior: Bound

import MarathonApp.Browser
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Rectangle {
    id: settingsPage

    property bool isPrivateMode: false
    property string searchEngine: "Google"
    property string searchEngineUrl: "https://www.google.com/search?q="
    property string homepage: "https://www.google.com"

    signal clearHistoryRequested
    signal clearCookiesRequested

    function goBack() {
        if (settingsStack.depth <= 1)
            return false;
        settingsStack.currentItem.requestBack(); // qmllint disable missing-property
        return true;
    }

    color: MColors.background

    StackView {
        id: settingsStack

        anchors.fill: parent
        initialItem: mainSettingsComponent

        Component {
            id: mainSettingsComponent

            ListView {
                clip: true
                spacing: 0
                model: [
                    {
                        "type": "toggle",
                        "title": "Private Browsing",
                        "subtitle": "Don't save history or cookies",
                        "iconName": "eye-off",
                        "value": settingsPage.isPrivateMode
                    },
                    {
                        "type": "button",
                        "title": "Clear History",
                        "subtitle": "Remove all browsing history",
                        "iconName": "trash-2"
                    },
                    {
                        "type": "button",
                        "title": "Clear Cookies",
                        "subtitle": "Remove all stored website data",
                        "iconName": "trash-2"
                    },
                    {
                        "type": "chevron",
                        "title": "Search Engine",
                        "subtitle": settingsPage.searchEngine,
                        "iconName": "search"
                    },
                    {
                        "type": "chevron",
                        "title": "Homepage",
                        "subtitle": settingsPage.homepage,
                        "iconName": "home"
                    }
                ]

                delegate: MSettingsListItem {
                    id: settingDelegate

                    required property var modelData

                    title: settingDelegate.modelData.title
                    subtitle: settingDelegate.modelData.subtitle
                    iconName: settingDelegate.modelData.iconName
                    showChevron: settingDelegate.modelData.type === "chevron"
                    showToggle: settingDelegate.modelData.type === "toggle"
                    toggleValue: settingDelegate.modelData.type === "toggle" ? settingDelegate.modelData.value : false
                    onSettingClicked: {
                        Logger.info("BrowserSettings", "Clicked: " + settingDelegate.modelData.title);
                        if (settingDelegate.modelData.title === "Clear History")
                            settingsPage.clearHistoryRequested();
                        else if (settingDelegate.modelData.title === "Clear Cookies")
                            settingsPage.clearCookiesRequested();
                        else if (settingDelegate.modelData.title === "Search Engine")
                            settingsStack.push(searchEngineComponent);
                        else if (settingDelegate.modelData.title === "Homepage")
                            settingsStack.push(homepageComponent);
                    }
                    onToggleChanged: value => {
                        if (settingDelegate.modelData.title === "Private Browsing") {
                            settingsPage.isPrivateMode = value;
                            Logger.info("BrowserSettings", "Private mode: " + value);
                        }
                    }
                }
            }
        }

        Component {
            id: searchEngineComponent

            SearchEnginePage {
                currentSearchEngine: settingsPage.searchEngine
                onSearchEngineSelected: (name, url) => {
                    settingsPage.searchEngine = name;
                    settingsPage.searchEngineUrl = url;
                    Logger.info("BrowserSettings", "Search engine changed to: " + name);
                    settingsStack.pop();
                }
                onBackRequested: settingsStack.pop()
            }
        }

        Component {
            id: homepageComponent

            HomepagePage {
                currentHomepage: settingsPage.homepage
                onHomepageChanged: url => {
                    settingsPage.homepage = url;
                    Logger.info("BrowserSettings", "Homepage changed to: " + url);
                    settingsStack.pop();
                }
                onBackRequested: settingsStack.pop()
            }
        }
    }
}
