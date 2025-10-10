import QtQuick
import "../theme"
import "../stores"

Item {
    id: appGrid
    
    signal pageChanged(int currentPage, int totalPages)
    signal appLaunched(var app)
    signal longPress()
    
    property int columns: 4
    property int rows: 4
    property int currentPage: 0
    property int totalPages: Math.ceil(AppStore.apps.length / (columns * rows))
    
    Component.onCompleted: console.log("✅ APP GRID LOADED with", AppStore.apps.length, "apps")
    
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: console.log("📱 APP GRID AREA PRESSED")
        onClicked: console.log("📱 APP GRID AREA CLICKED")
    }
    
    ListView {
        id: pageView
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.DragAndOvershootBounds
        clip: true
        interactive: true
        flickableDirection: Flickable.HorizontalFlick
        z: 10
        
        model: totalPages
        
        delegate: Item {
            width: pageView.width
            height: pageView.height
            
            Grid {
                anchors.fill: parent
                anchors.margins: 16
                columns: appGrid.columns
                rows: appGrid.rows
                spacing: 16
                
                Repeater {
                    model: {
                        var startIdx = index * (appGrid.columns * appGrid.rows)
                        var endIdx = Math.min(startIdx + (appGrid.columns * appGrid.rows), AppStore.apps.length)
                        return AppStore.apps.slice(startIdx, endIdx)
                    }
                    
                    Item {
                        width: (parent.width - (appGrid.columns - 1) * parent.spacing) / appGrid.columns
                        height: (parent.height - (appGrid.rows - 1) * parent.spacing) / appGrid.rows
                        
                        scale: iconMouseArea.pressed ? 0.85 : 1.0
                        opacity: iconMouseArea.pressed ? 0.7 : 1.0
                        
                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                        
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                source: modelData.icon
                                width: 72
                                height: 72
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                color: WallpaperStore.isDark ? Colors.text : "#000000"
                                font.pixelSize: 20
                                font.family: Typography.fontFamily
                            }
                        }
                        
                        MouseArea {
                            id: iconMouseArea
                            anchors.fill: parent
                            z: 200
                            
                            onPressed: {
                                console.log("APP PRESS DETECTED:", modelData.name)
                            }
                            
                            onClicked: {
                                console.log("============ APP CLICKED:", modelData.name, "id:", modelData.id, "============")
                                AppStore.launchApp(modelData.id)
                                appLaunched(modelData)
                            }
                            
                            onPressAndHold: {
                                console.log("App long press:", modelData.id)
                                longPress()
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

