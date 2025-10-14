import QtQuick
import MarathonOS.Shell

Item {
    id: appGrid
    
    signal pageChanged(int currentPage, int totalPages)
    signal appLaunched(var app)
    signal longPress()
    
    property int columns: 4
    property int rows: 4
    property int currentPage: 0
    property int totalPages: Math.ceil(AppStore.apps.length / (columns * rows))
    
    Component.onCompleted: Logger.info("AppGrid", "Initialized with " + AppStore.apps.length + " apps")
    
    ListView {
        id: pageView
        anchors.fill: parent
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.DragAndOvershootBounds
        clip: true
        interactive: true
        flickableDirection: Flickable.HorizontalFlick
        z: 10
        
        // Performance optimizations
        cacheBuffer: pageView.width * 2  // Preload 2 pages
        reuseItems: true  // Reuse delegate items
        
        model: totalPages
        
        delegate: Item {
            width: pageView.width
            height: pageView.height
            
            Grid {
                anchors.fill: parent
                anchors.margins: 12
                columns: appGrid.columns
                rows: appGrid.rows
                spacing: 12
                
                Repeater {
                    model: {
                        var startIdx = index * (appGrid.columns * appGrid.rows)
                        var endIdx = Math.min(startIdx + (appGrid.columns * appGrid.rows), AppStore.apps.length)
                        return AppStore.apps.slice(startIdx, endIdx)
                    }
                    
                    Item {
                        width: (parent.width - (appGrid.columns - 1) * parent.spacing) / appGrid.columns
                        height: (parent.height - (appGrid.rows - 1) * parent.spacing) / appGrid.rows
                        
                        transform: [
                            Scale {
                                origin.x: width / 2
                                origin.y: height / 2
                                xScale: iconMouseArea.pressed ? 0.95 : 1.0
                                yScale: iconMouseArea.pressed ? 0.95 : 1.0
                                
                                Behavior on xScale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on yScale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            },
                            Translate {
                                y: iconMouseArea.pressed ? -2 : 0
                                
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        ]
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72
                                height: 72
                                radius: 6
                                color: Qt.rgba(255, 255, 255, 0.04)
                                border.width: 1
                                border.color: iconMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.6) : Qt.rgba(255, 255, 255, 0.12)
                                layer.enabled: true
                                
                                Behavior on border.color {
                                    ColorAnimation { duration: 150 }
                                }
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: parent.radius - 1
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(255, 255, 255, 0.03)
                                }
                                
                                Image {
                                    anchors.centerIn: parent
                                    source: modelData.icon
                                    width: parent.width - 8
                                    height: parent.height - 8
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                    cache: true
                                }
                                
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: -4
                                    anchors.rightMargin: -4
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: "#E63946"
                                    border.width: 2
                                    border.color: Colors.background
                                    visible: {
                                        var count = NotificationService.getNotificationCountForApp(modelData.id)
                                        return count > 0
                                    }
                                    
                                    Text {
                                        text: {
                                            var count = NotificationService.getNotificationCountForApp(modelData.id)
                                            return count > 9 ? "9+" : count.toString()
                                        }
                                        color: Colors.text
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.family: Typography.fontFamily
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                            
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                color: WallpaperStore.isDark ? Colors.text : "#000000"
                                font.pixelSize: Typography.sizeSmall
                                font.family: Typography.fontFamily
                                font.weight: Font.DemiBold
                            }
                        }
                        
                        MouseArea {
                            id: iconMouseArea
                            anchors.fill: parent
                            z: 200
                            
                            onPressed: {
                                Logger.debug("AppGrid", "App pressed: " + modelData.name)
                                HapticService.light()
                            }
                            
                            onClicked: {
                                Logger.info("AppGrid", "App launched: " + modelData.name)
                                appLaunched(modelData)
                                HapticService.medium()
                            }
                            
                            onPressAndHold: {
                                Logger.info("AppGrid", "App long-pressed: " + modelData.name)
                                var globalPos = mapToItem(appGrid.parent, mouseX, mouseY)
                                HapticService.heavy()
                                
                                if (appGrid.parent && appGrid.parent.parent && appGrid.parent.parent.parent) {
                                    var shell = appGrid.parent.parent.parent
                                    if (shell.appContextMenu) {
                                        shell.appContextMenu.show(modelData, globalPos)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        onCurrentIndexChanged: {
            currentPage = currentIndex
            pageChanged(currentPage, totalPages)
        }
    }
    
    function snapToPage(pageIndex) {
        pageView.positionViewAtIndex(pageIndex, ListView.Beginning)
    }
}

