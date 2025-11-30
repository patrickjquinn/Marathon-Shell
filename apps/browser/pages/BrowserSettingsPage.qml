import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers

Rectangle {
    id: settingsPage
    color: MColors.background

    signal clearHistoryRequested
    signal clearCookiesRequested

    property bool isPrivateMode: false
    property string searchEngine: "Google"
    property string searchEngineUrl: "https://www.google.com/search?q="
    property string homepage: "https://www.google.com"

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
                        type: "toggle",
                        title: "Private Browsing",
                        subtitle: "Don't save history or cookies",
                        iconName: "eye-off",
                        value: settingsPage.isPrivateMode
                    },
                    {
                        type: "button",
                        title: "Clear History",
                        subtitle: "Remove all browsing history",
                        iconName: "trash-2"
                    },
                    {
                        type: "button",
                        title: "Clear Cookies",
                        subtitle: "Remove all stored website data",
                        iconName: "trash-2"
                    },
                    {
                        type: "chevron",
                        title: "Search Engine",
                        subtitle: settingsPage.searchEngine,
                        iconName: "search"
                    },
                    {
                        type: "chevron",
                        title: "Homepage",
                        subtitle: settingsPage.homepage,
                        iconName: "home"
                    }
                ]

                delegate: MSettingsListItem {
                    title: modelData.title
                    subtitle: modelData.subtitle
                    iconName: modelData.iconName
                    showChevron: modelData.type === "chevron"
                    showToggle: modelData.type === "toggle"
                    toggleValue: modelData.type === "toggle" ? modelData.value : false

                    onSettingClicked: {
                        Logger.info("BrowserSettings", "Clicked: " + modelData.title);

                        if (modelData.title === "Clear History") {
                            settingsPage.clearHistoryRequested();
                        } else if (modelData.title === "Clear Cookies") {
                            settingsPage.clearCookiesRequested();
                        } else if (modelData.title === "Search Engine") {
                            settingsStack.push(searchEngineComponent);
                        } else if (modelData.title === "Homepage") {
                            settingsStack.push(homepageComponent);
                        }
                    }

                    onToggleChanged: value => {
                        if (modelData.title === "Private Browsing") {
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
