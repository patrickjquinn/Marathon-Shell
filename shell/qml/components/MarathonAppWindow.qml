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
    property bool isLoadingComponent: false
    
    signal closed()
    signal minimized()
    
    // Loading splash (shown while component is loading)
    Rectangle {
        id: loadingSplash
        anchors.fill: parent
        color: Colors.background
        visible: appWindow.isLoadingComponent
        z: 1000
        
        Column {
            anchors.centerIn: parent
            spacing: 24
            
            Image {
                width: 128
                height: 128
                source: appWindow.appIcon || "qrc:/images/icons/lucide/grid.svg"
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                smooth: true
            }
            
            Text {
                text: "Loading " + (appWindow.appName || "app") + "..."
                color: Colors.textSecondary
                font.pixelSize: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    
    function show(id, name, icon, type, surface, sid) {
        console.log("=============== SHOW() CALLED ===============")
        console.log("  id:", id)
        console.log("  name:", name)
        console.log("  type:", type)
        console.log("  surface:", surface)
        console.log("  sid:", sid)
        
        appId = id
        appName = name
        appIcon = icon
        appType = type || "marathon"
        waylandSurface = surface || null
        surfaceId = sid || -1
        
        console.log("  appType set to:", appType)
        Logger.info("AppWindow", "Showing app window for: " + name + " (type: " + appType + ")")
        
        // CRITICAL: Cleanup connections and unparent the current app instance BEFORE switching
        if (appContentLoader.item) {
            // Trigger cleanup in the container's onDestruction
            // This will disconnect signals before unparenting
            if (appContentLoader.item.children.length > 0) {
                var currentChild = appContentLoader.item.children[0]
                if (currentChild && currentChild.parent) {
                    Logger.info("AppWindow", "Unparenting previous app instance")
                    currentChild.parent = null
                    currentChild.visible = false
                }
            }
        }
        
        if (appType === "native") {
            // Check if native app instance already exists in lifecycle manager
            var existingNativeInstance = null
            if (typeof AppLifecycleManager !== 'undefined') {
                existingNativeInstance = AppLifecycleManager.getAppInstance(id)
            }
            
            if (existingNativeInstance) {
                // Reuse existing native app instance - just reparent it
                console.log("[NATIVE APP] Reusing existing instance:", id)
                Logger.info("AppWindow", "Reusing existing native app instance: " + id)
                existingNativeInstance.visible = true
                appWindow.pendingAppInstance = existingNativeInstance
                // FORCE reload by clearing first
                appContentLoader.sourceComponent = undefined
                appContentLoader.sourceComponent = appInstanceContainer
            } else {
                // Create new native app instance using dynamic loading
                console.log("[NATIVE APP] Creating new instance:", id)
                Logger.info("AppWindow", "Creating new native app instance: " + id)
                
                appWindow.isLoadingComponent = true
                Logger.info("AppWindow", "Showing loading splash...")
                
                var component = Qt.createComponent("../apps/native/NativeAppWindow.qml", Component.Asynchronous)
                
                function finishCreation() {
                    if (component.status === Component.Ready) {
                        var nativeInstance = component.createObject(null, {
                            "nativeAppId": id,
                            "nativeTitle": name,
                            "nativeAppIcon": icon,
                            "waylandSurface": surface,
                            "surfaceId": sid
                        })
                        if (nativeInstance) {
                            appWindow.pendingAppInstance = nativeInstance
                            appContentLoader.sourceComponent = undefined
                            appContentLoader.sourceComponent = appInstanceContainer
                            appWindow.isLoadingComponent = false
                            Logger.info("AppWindow", "Native app instance created successfully: " + id)
                        } else {
                            appWindow.isLoadingComponent = false
                            Logger.error("AppWindow", "Failed to create native app instance: " + id)
                        }
                    } else if (component.status === Component.Error) {
                        appWindow.isLoadingComponent = false
                        Logger.error("AppWindow", "Error loading NativeAppWindow: " + component.errorString())
                    }
                }
                
                if (component.status === Component.Ready) {
                    finishCreation()
                } else {
                    component.statusChanged.connect(finishCreation)
                }
            }
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
                    existingInstance.visible = true
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
        
        // Note: Signal connections are handled in appInstanceContainer Component.onCompleted
        // to ensure proper cleanup on destruction
        
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
            
            property var appInstance: null
            property var minimizeConnection: null
            property var closedConnection: null
            
            Component.onCompleted: {
                if (appWindow.pendingAppInstance) {
                    appInstance = appWindow.pendingAppInstance
                    appWindow.pendingAppInstance = null
                    
                    appInstance.parent = this
                    appInstance.anchors.fill = this
                    
                    // Capture values to avoid accessing potentially destroyed appWindow later
                    var capturedAppName = appWindow.appName
                    var capturedAppId = appWindow.appId
                    var capturedWindow = appWindow  // Capture window reference
                    
                    if (appInstance.minimizeRequested) {
                        minimizeConnection = appInstance.minimizeRequested.connect(function() {
                            Logger.info("AppWindow", "MApp minimize requested: " + capturedAppName)
                            if (capturedWindow) {
                                capturedWindow.minimized()
                            }
                        })
                    }
                    
                    if (appInstance.closed) {
                        closedConnection = appInstance.closed.connect(function() {
                            Logger.info("AppWindow", "MApp closed: " + capturedAppName)
                            if (capturedWindow) {
                                capturedWindow.hide()
                            }
                        })
                    }
                    
                    Logger.info("AppWindow", "MApp instance connected: " + capturedAppId)
                }
            }
            
            Component.onDestruction: {
                if (appInstance) {
                    if (minimizeConnection && appInstance.minimizeRequested) {
                        appInstance.minimizeRequested.disconnect(minimizeConnection)
                    }
                    if (closedConnection && appInstance.closed) {
                        appInstance.closed.disconnect(closedConnection)
                    }
                }
            }
        }
    }
    
    Loader {
        id: appContentLoader
        anchors.fill: parent
        asynchronous: false  // Changed to synchronous to reduce app launch latency
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

