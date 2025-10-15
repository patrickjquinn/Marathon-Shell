import QtQuick
import MarathonOS.Shell

Rectangle {
    id: appWindow
    anchors.fill: parent
    color: Colors.surface
    focus: true
    
    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    property string appType: "marathon"
    property var waylandSurface: null
    property int surfaceId: -1
    property var pendingAppInstance: null
    
    signal closed()
    signal minimized()
    
    function show(id, name, icon, type, surface, sid) {
        appId = id
        appName = name
        appIcon = icon
        appType = type || "marathon"
        waylandSurface = surface || null
        surfaceId = sid || -1
        
        Logger.info("AppWindow", "Showing app window for: " + name + " (type: " + appType + ")")
        
        if (appType === "native") {
            // Load native Wayland app
            appContentLoader.setSource("../apps/native/NativeAppWindow.qml", {
                "nativeAppId": id,
                "nativeTitle": name,
                "waylandSurface": surface,
                "surfaceId": sid
            })
        } else {
            // Check if app exists in registry
            var appInfo = MarathonAppRegistry.getApp(id)
            
            if (appInfo && appInfo.absolutePath && appInfo.entryPoint) {
                // Check if app instance already exists in lifecycle manager
                var existingInstance = null
                if (typeof AppLifecycleManager !== 'undefined') {
                    existingInstance = AppLifecycleManager.getAppInstance(id)
                }
                
                if (existingInstance) {
                    // Reuse existing instance - just reparent it
                    Logger.info("AppWindow", "Reusing existing app instance: " + id)
                    appWindow.pendingAppInstance = existingInstance
                    // FORCE reload by clearing first
                    appContentLoader.sourceComponent = undefined
                    appContentLoader.sourceComponent = appInstanceContainer
                } else {
                    // Load external Marathon app dynamically (creates new instance)
                    Logger.info("AppWindow", "Loading external app from: " + appInfo.absolutePath)
                    
                    var appInstance = MarathonAppLoader.loadApp(id)
                    
                    if (appInstance) {
                        // Store instance and set component - container will pick it up
                        appWindow.pendingAppInstance = appInstance
                        // FORCE reload by clearing first
                        appContentLoader.sourceComponent = undefined
                        appContentLoader.sourceComponent = appInstanceContainer
                        Logger.info("AppWindow", "External app loaded successfully: " + id)
                    } else {
                        Logger.error("AppWindow", "Failed to load external app: " + id)
                        // Fallback to template
                        appContentLoader.setSource("../apps/template/TemplateApp.qml", {
                            "_appId": id,
                            "_appName": name,
                            "_appIcon": icon
                        })
                    }
                }
            } else {
                // Load placeholder template app
                Logger.info("AppWindow", "Loading template app for: " + id)
                appContentLoader.setSource("../apps/template/TemplateApp.qml", {
                    "_appId": id,
                    "_appName": name,
                    "_appIcon": icon
                })
            }
        }
        
        if (appContentLoader.item) {
            if (appContentLoader.item.minimizeRequested) {
                appContentLoader.item.minimizeRequested.connect(function() {
                    Logger.info("AppWindow", "App minimize requested: " + name)
                    minimized()
                })
            }
        }
        
        visible = true
        forceActiveFocus()
        slideIn.start()
    }
    
    function hide() {
        appContentLoader.source = ""
        slideOut.start()
    }
    
    NumberAnimation {
        id: slideIn
        target: appWindow
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 300
        easing.type: Easing.OutCubic
    }
    
    NumberAnimation {
        id: slideOut
        target: appWindow
        property: "opacity"
        from: 1.0
        to: 0.0
        duration: 300
        easing.type: Easing.InCubic
        onFinished: {
            appWindow.visible = false
            closed()
        }
    }
    
    Component {
        id: appInstanceContainer
        Item {
            anchors.fill: parent
            
            Component.onCompleted: {
                if (appWindow.pendingAppInstance) {
                    var appInstance = appWindow.pendingAppInstance
                    appWindow.pendingAppInstance = null
                    
                    appInstance.parent = this
                    appInstance.anchors.fill = this
                    
                    if (appInstance.minimizeRequested) {
                        appInstance.minimizeRequested.connect(function() {
                            Logger.info("AppWindow", "MApp minimize requested: " + appWindow.appName)
                            appWindow.minimized()
                        })
                    }
                    
                    if (appInstance.closed) {
                        appInstance.closed.connect(function() {
                            Logger.info("AppWindow", "MApp closed: " + appWindow.appName)
                            appWindow.hide()
                        })
                    }
                    
                    Logger.info("AppWindow", "MApp instance connected: " + appWindow.appId)
                }
            }
        }
    }
    
    Loader {
        id: appContentLoader
        anchors.fill: parent
        asynchronous: true
        visible: status === Loader.Ready && item !== null
        opacity: status === Loader.Ready ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation { 
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
        
        onStatusChanged: {
            if (status === Loader.Error) {
                Logger.error("AppWindow", "Failed to load app content for: " + appId)
            } else if (status === Loader.Ready) {
                Logger.info("AppWindow", "App content loaded successfully for: " + appId)
            }
        }
    }
    
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            console.log("[AppWindow] Back/Escape key pressed")
            AppStore.closeApp(appId)
            hide()
            event.accepted = true
        }
    }
}

