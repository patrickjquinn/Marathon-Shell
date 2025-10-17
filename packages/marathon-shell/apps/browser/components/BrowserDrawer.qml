import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Theme
import "../pages"

Rectangle {
    id: drawer
    anchors.fill: parent
    color: MColors.backgroundDark
    
    signal closed()
    signal tabSelected(int tabId)
    signal newTabRequested()
    signal bookmarkSelected(string url)
    signal historySelected(string url)
    
    property int selectedTabIndex: 0
    property alias contentStack: contentStack
    property alias tabsPage: tabsPage
    property alias bookmarksPage: bookmarksPage
    property alias historyPage: historyPage
    property alias settingsPage: settingsPage
    
    Column {
        anchors.fill: parent
        spacing: 0
                    
        Row {
            id: drawerTabs
            width: parent.width
            height: Constants.touchTargetSmall
            z: 0
            
            Repeater {
                model: [
                    { name: "Tabs", icon: "layers" },
                    { name: "Bookmarks", icon: "star" },
                    { name: "History", icon: "clock" },
                    { name: "Settings", icon: "settings" }
                ]
                
                Item {
                    width: drawer.width / 4
                    height: Constants.touchTargetSmall
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: Constants.borderRadiusSharp
                        color: index === drawer.selectedTabIndex ? MColors.surface2 : MColors.surface
                        border.width: Constants.borderWidthThin
                        border.color: index === drawer.selectedTabIndex ? MColors.accentBright : MColors.borderOuter
                        antialiasing: Constants.enableAntialiasing
                        
                        transform: Translate {
                            y: tabMouseArea.pressed ? -1 : 0
                            
                            Behavior on y {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                        
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Constants.borderRadiusSharp
                            color: "transparent"
                            border.width: Constants.borderWidthThin
                            border.color: MColors.borderInner
                            antialiasing: Constants.enableAntialiasing
                        }
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            
                            Icon {
                                name: modelData.icon
                                size: Constants.iconSizeSmall
                                color: index === drawer.selectedTabIndex ? MColors.accentBright : MColors.textSecondary
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: index === drawer.selectedTabIndex ? 1.0 : (tabMouseArea.pressed ? 0.8 : 0.6)
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                            
                            Text {
                                text: modelData.name
                                color: index === drawer.selectedTabIndex ? MColors.accentBright : MColors.textSecondary
                                font.pixelSize: MTypography.sizeXSmall
                                font.family: MTypography.fontFamily
                                font.weight: index === drawer.selectedTabIndex ? Font.DemiBold : Font.Normal
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: index === drawer.selectedTabIndex ? 1.0 : (tabMouseArea.pressed ? 0.8 : 0.7)
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                        }
                    }
                    
                    MouseArea {
                        id: tabMouseArea
                        anchors.fill: parent
                        z: 100
                        onClicked: {
                            drawer.selectedTabIndex = index
                            Logger.info("BrowserDrawer", "Switched to tab: " + modelData.name)
                        }
                    }
                }
            }
        }
        
        StackLayout {
            id: contentStack
            width: parent.width
            height: parent.height - drawerTabs.height
            currentIndex: drawer.selectedTabIndex
            
            TabsPage {
                id: tabsPage
                onTabSelected: (tabId) => drawer.tabSelected(tabId)
                onNewTabRequested: drawer.newTabRequested()
            }
            
            BookmarksPage {
                id: bookmarksPage
                onBookmarkSelected: (url) => {
                    drawer.bookmarkSelected(url)
                    drawer.closed()
                }
            }
            
            HistoryPage {
                id: historyPage
                onHistorySelected: (url) => {
                    drawer.historySelected(url)
                    drawer.closed()
                }
            }
            
            BrowserSettingsPage {
                id: settingsPage
            }
        }
    }
}

