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
    
    signal closed()
    signal minimized()
    
    function show(id, name, icon, type, surface, sid) {
        appId = id
        appName = name
        appIcon = icon
        appType = type || "marathon"
        waylandSurface = surface || null
        surfaceId = sid || -1
        
        if (appType === "native") {
            appContentLoader.setSource("../apps/native/NativeAppWindow.qml", {
                "nativeAppId": id,
                "nativeTitle": name,
                "waylandSurface": surface,
                "surfaceId": sid
            })
        } else {
            appContentLoader.setSource("../apps/template/TemplateApp.qml", {
                "_appId": id,
                "_appName": name,
                "_appIcon": icon
            })
        }
        
        if (appContentLoader.item) {
            appContentLoader.item.minimizeRequested.connect(function() {
                Logger.info("AppWindow", "App minimize requested: " + name)
                minimized()
            })
        }
        
        visible = true
        forceActiveFocus()
        slideIn.start()
        Logger.info("AppWindow", "Showing app window for: " + name + " (type: " + appType + ")")
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

