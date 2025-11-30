import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "components"

MApp {
    id: terminalApp
    appId: "terminal"
    appName: "Terminal"
    appIcon: "assets/icon.svg"

    property int currentTabIndex: 0
    property var tabs: []
    property int nextTabId: 1

    function createNewTab() {
        var tabId = nextTabId++;
        var tab = {
            id: tabId,
            title: "Terminal " + tabId,
            session: null
        };
        tabs.push(tab);
        currentTabIndex = tabs.length - 1;
        tabsChanged();

        Logger.info("Terminal", "Created new tab: " + currentTabIndex);
    }

    function closeTab(index) {
        if (tabs.length === 1) {
            Logger.info("Terminal", "Cannot close last tab");
            return;
        }

        if (index >= 0 && index < tabs.length) {
            var tab = tabs[index];
            // Session cleanup is handled by the Item destruction

            tabs.splice(index, 1);

            if (currentTabIndex >= tabs.length) {
                currentTabIndex = tabs.length - 1;
            }

            tabsChanged();
            Logger.info("Terminal", "Closed tab: " + index);
        }
    }

    Component.onCompleted: {
        createNewTab();
    }

    content: Rectangle {
        id: contentRoot
        anchors.fill: parent
        color: MColors.background

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Terminal Content Area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Repeater {
                    model: terminalApp.tabs.length

                    TerminalSession {
                        anchors.fill: parent
                        visible: index === currentTabIndex

                        Component.onCompleted: {
                            var tab = terminalApp.tabs[index];
                            if (tab) {
                                tab.session = this;
                            }
                            start();
                        }

                        onSessionFinished: {
                            Logger.info("Terminal", "Session finished for tab " + index);
                            if (terminalApp.tabs.length > 1) {
                                terminalApp.closeTab(index);
                            } else {
                                start(); // Restart if last tab
                            }
                        }
                    }
                }
            }

            // Tab Bar (Bottom)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: MColors.surface

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: MColors.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: MSpacing.sm
                    spacing: MSpacing.sm

                    // Scrollable tab area
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                        Row {
                            height: parent.height
                            spacing: MSpacing.sm

                            Repeater {
                                model: terminalApp.tabs.length

                                TerminalTabButton {
                                    height: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    title: {
                                        var tab = terminalApp.tabs[index];
                                        if (tab && tab.session) {
                                            return tab.session.title || tab.title;
                                        }
                                        return tab ? tab.title : "";
                                    }
                                    active: index === currentTabIndex
                                    canClose: terminalApp.tabs.length > 1

                                    onClicked: currentTabIndex = index
                                    onCloseClicked: terminalApp.closeTab(index)
                                }
                            }
                        }
                    }

                    // New Tab Button Wrapper for Centering
                    Item {
                        Layout.preferredWidth: 48
                        Layout.fillHeight: true

                        MCircularIconButton {
                            anchors.centerIn: parent
                            iconName: "plus"
                            variant: "secondary"
                            buttonSize: 36
                            iconSize: 20
                            onClicked: terminalApp.createNewTab()
                        }
                    }
                }
            }

            // Virtual Key Row (Bottom)
            VirtualKeyRow {
                Layout.fillWidth: true
                Layout.preferredHeight: 48

                onKeyTriggered: (key, modifiers) => {
                    var tab = terminalApp.tabs[currentTabIndex];
                    if (tab && tab.session) {
                        tab.session.sendKey(key, "", modifiers);
                    }
                }
            }
        }
    }
}
