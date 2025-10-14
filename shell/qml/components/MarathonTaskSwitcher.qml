import QtQuick
import MarathonOS.Shell
import "."

Item {
    id: taskSwitcher
    
    signal closed()
    signal taskSelected(var task)
    
    MouseArea {
        anchors.fill: parent
        enabled: TaskManagerStore.taskCount > 0
        onClicked: {
            closed()
        }
    }
    
    GridView {
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2  // 2x2 grid
        clip: true
        
        model: TaskManagerStore.runningTasks
        
        delegate: Item {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            
            Rectangle {
                id: cardRoot
                anchors.fill: parent
                anchors.margins: 8
                color: Qt.rgba(255, 255, 255, 0.04)
                radius: 4
                border.width: 1
                border.color: cardMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.4) : Qt.rgba(255, 255, 255, 0.12)
                layer.enabled: true
                
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: cardMouseArea.pressed ? 0.98 : 1.0
                        yScale: cardMouseArea.pressed ? 0.98 : 1.0
                        
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
                        y: cardMouseArea.pressed ? -2 : 0
                        
                        Behavior on y {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]
                
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
                
                Column {
                    anchors.fill: parent
                    
                    Rectangle {
                        width: parent.width
                        height: parent.height - 50
                        color: Colors.backgroundDark
                        radius: parent.parent.radius
                        
                        Loader {
                            id: appPreview
                            anchors.fill: parent
                            anchors.margins: 2
                            active: true
                            asynchronous: true
                            
                            sourceComponent: Item {
                                anchors.fill: parent
                                clip: true
                                
                                Item {
                                    id: livePreview
                                    width: 720
                                    height: 1280
                                    
                                    // Scale to fill width, anchored to top-left
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    scale: parent.width / 720
                                    transformOrigin: Item.TopLeft
                                    
                                    Loader {
                                        width: 720
                                        height: 1280
                                        active: modelData.type === "marathon" && modelData.appId !== "settings"
                                        source: (modelData.type === "marathon" && modelData.appId !== "settings") ? "../apps/template/TemplateApp.qml" : ""
                                        visible: status === Loader.Ready
                                        
                                        onLoaded: {
                                            if (item) {
                                                item._appId = modelData.appId
                                                item._appName = modelData.title
                                                item._appIcon = modelData.icon
                                            }
                                        }
                                    }
                                    
                                    Loader {
                                        width: 720
                                        height: 1280
                                        active: modelData.type === "marathon" && modelData.appId === "settings"
                                        source: (modelData.type === "marathon" && modelData.appId === "settings") ? "../apps/settings/SettingsApp.qml" : ""
                                        visible: status === Loader.Ready
                                    }
                                    
                                    Loader {
                                        width: 720
                                        height: 1280
                                        active: modelData.type === "native"
                                        source: modelData.type === "native" ? "../apps/native/NativeAppWindow.qml" : ""
                                        visible: status === Loader.Ready
                                        
                                        onLoaded: {
                                            if (item && modelData.surfaceId >= 0) {
                                                item.surfaceId = modelData.surfaceId
                                                item.nativeAppId = modelData.appId
                                                item.nativeTitle = modelData.title
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        MouseArea {
                            id: cardMouseArea
                            anchors.fill: parent
                            
                            
                            onClicked: {
                                if (modelData.appId === "settings") {
                                    UIStore.openSettings()
                                } else {
                                    UIStore.restoreApp(modelData.appId, modelData.title, modelData.icon)
                                }
                                closed()
                            }
                        }
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: 50
                        color: Colors.surfaceLight
                        radius: 0
                        
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: modelData.icon
                                width: 32
                                height: 32
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 80
                                spacing: 2
                                
                                Text {
                                    text: modelData.title
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeSmall
                                    font.weight: Font.DemiBold
                                    font.family: Typography.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                
                                Text {
                                    text: modelData.subtitle || "Running"
                                    color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeXSmall
                                    font.family: Typography.fontFamily
                                    opacity: 0.7
                                }
                            }
                            
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: Colors.cornerRadiusSmall
                                    color: Colors.surfaceLight
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        color: Colors.text
                                        font.pixelSize: Typography.sizeLarge
                                        font.weight: Font.Bold
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        z: 1000
                                        onClicked: {
                                            Logger.info("TaskSwitcher", "Closing task: " + modelData.appId)
                                            TaskManagerStore.closeTask(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
            }
        }
    }
    
    Behavior on opacity {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
    
    scale: visible ? 1.0 : 0.95
    Behavior on scale {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
}
