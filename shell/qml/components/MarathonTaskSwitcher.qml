import QtQuick
import MarathonOS.Shell
import "."

Item {
    id: taskSwitcher
    
    signal closed()
    signal taskSelected(var task)
    
    // Component definitions for preview instances (each delegate gets fresh instance)
    Component {
        id: templateAppComponent
        Loader {
            width: 720
            height: 1280
            source: "../apps/template/TemplateApp.qml"
            asynchronous: true
        }
    }
    
    Component {
        id: settingsAppComponent
        Loader {
            width: 720
            height: 1280
            source: "../apps/settings/SettingsApp.qml"
            asynchronous: true
        }
    }
    
    // Background click to close (but don't steal events from cards)
    MouseArea {
        anchors.fill: parent
        enabled: TaskModel.taskCount > 0
        propagateComposedEvents: true  // Let card MouseAreas handle their events
        z: -1  // Behind the GridView
        onClicked: (mouse) => {
            // Only close if clicking empty space (not on a card)
            mouse.accepted = false
            closed()
        }
    }
    
    Connections {
        target: TaskModel
        function onTaskCountChanged() {
            Logger.info("TaskSwitcher", "TaskModel count changed: " + TaskModel.taskCount)
        }
    }
    
    GridView {
        id: taskGrid
        anchors.fill: parent
        anchors.margins: 16
        anchors.rightMargin: TaskModel.taskCount > 4 ? 48 : 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2
        clip: true
        
        // Only allow vertical scrolling
        flickableDirection: Flickable.VerticalFlick
        interactive: TaskModel.taskCount > 4  // Only scrollable if more than 1 page
        
        // Pagination settings - snap to full pages (2 rows = 4 apps)
        snapMode: GridView.NoSnap  // Disable automatic snap, use custom
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        
        // Smooth scrolling with strong snap effect
        flickDeceleration: 8000
        maximumFlickVelocity: 3000
        
        // Custom page snapping
        onMovementEnded: {
            var page = Math.round(contentY / height)
            var targetY = page * height
            snapAnimation.to = targetY
            snapAnimation.start()
        }
        
        onFlickEnded: onMovementEnded()
        
        NumberAnimation {
            id: snapAnimation
            target: taskGrid
            property: "contentY"
            duration: 200
            easing.type: Easing.OutCubic
        }
        
        model: TaskModel
        
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true
                
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
                border.color: cardDragArea.pressed ? Qt.rgba(20, 184, 166, 0.4) : Qt.rgba(255, 255, 255, 0.12)
                layer.enabled: true
                
                // FULL CARD MouseArea for dragging (covers preview AND banner)
                MouseArea {
                    id: cardDragArea
                    anchors.fill: parent
                    z: 50  // Below close button (z: 1000) but above content
                    preventStealing: true  // Don't let parent steal drag
                    
                    property real startY: 0
                    property real startTime: 0
                    property real lastY: 0
                    property real lastTime: 0
                    property real dragDistance: 0
                    property bool isDragging: false
                    property real velocity: 0
                    property bool closeButtonClicked: false
                    
                    onPressed: function(mouse) {
                        // Check if click is on close button - let it handle
                        var buttonPos = closeButtonArea.mapToItem(cardDragArea, 0, 0)
                        var isOnButton = mouse.x >= buttonPos.x && 
                                        mouse.x <= buttonPos.x + closeButtonArea.width &&
                                        mouse.y >= buttonPos.y && 
                                        mouse.y <= buttonPos.y + closeButtonArea.height
                        
                        if (isOnButton) {
                            closeButtonClicked = true
                            mouse.accepted = false  // Let close button handle
                            return
                        }
                        
                        startY = mouse.y
                        startTime = Date.now()
                        lastY = mouse.y
                        lastTime = startTime
                        dragDistance = 0
                        isDragging = false
                        velocity = 0
                        closeButtonClicked = false
                        mouse.accepted = true
                    }
                    
                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            var now = Date.now()
                            var deltaTime = now - lastTime
                            var deltaY = mouse.y - lastY
                            
                            // Calculate instantaneous velocity
                            if (deltaTime > 0) {
                                velocity = deltaY / deltaTime
                            }
                            
                            dragDistance = mouse.y - startY
                            lastY = mouse.y
                            lastTime = now
                            
                            // Start dragging after 10px movement
                            if (Math.abs(dragDistance) > 10) {
                                isDragging = true
                            }
                        }
                    }
                    
                    onReleased: function(mouse) {
                        // If close button was clicked, ignore
                        if (closeButtonClicked) {
                            closeButtonClicked = false
                            return
                        }
                        
                        var totalTime = Date.now() - startTime
                        
                        // Use instantaneous velocity (more responsive to flicks)
                        // Flick up: velocity < -0.5 px/ms (more lenient)
                        // OR drag up > 50px (reduced from 80px)
                        var isFlickUp = velocity < -0.5
                        var isDragUp = dragDistance < -50
                        
                        if (isDragging && (isFlickUp || isDragUp)) {
                            Logger.info("TaskSwitcher", "Closing: " + model.appId + " (v: " + velocity.toFixed(2) + "px/ms, d: " + dragDistance.toFixed(0) + "px)")
                            
                            var taskIdToClose = model.id
                            
                            // Reset transform immediately to avoid ghost spacing
                            dragDistance = 0
                            isDragging = false
                            velocity = 0
                            
                            // Close task - GridView will remove delegate cleanly
                            TaskModel.closeTask(taskIdToClose)
                            
                            mouse.accepted = true
                        } else if (!isDragging && totalTime < 200) {
                            // Quick tap - open app
                            Logger.info("TaskSwitcher", "Opening task: " + model.appId)
                            var appId = model.appId
                            var appTitle = model.title
                            var appIcon = model.icon
                            
                            // Defer to avoid blocking
                            Qt.callLater(function() {
                                if (appId === "settings") {
                                    UIStore.openSettings()
                                } else {
                                    UIStore.restoreApp(appId, appTitle, appIcon)
                                }
                                closed()
                            })
                            mouse.accepted = true
                        } else {
                            // Drag but not past threshold
                            mouse.accepted = false
                        }
                        
                        dragDistance = 0
                        isDragging = false
                        velocity = 0
                    }
                }
                
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: cardDragArea.pressed ? 0.98 : 1.0
                        yScale: cardDragArea.pressed ? 0.98 : 1.0
                        
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
                        y: cardDragArea.isDragging ? cardDragArea.dragDistance : 
                           (cardDragArea.closeButtonClicked ? 0 : 
                            (cardDragArea.pressed ? -2 : 0))
                        
                        Behavior on y {
                            enabled: !cardDragArea.isDragging
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
                                            
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            scale: parent.width / 720
                                            transformOrigin: Item.TopLeft
                                            
                                            Loader {
                                                width: 720
                                                height: 1280
                                                active: model.type === "marathon" && model.appId !== "settings"
                                                visible: status === Loader.Ready
                                                
                                                sourceComponent: (model.type === "marathon" && model.appId !== "settings") ? templateAppComponent : null
                                                
                                                property string previewAppId: model.appId
                                                property string previewAppName: model.title
                                                property string previewAppIcon: model.icon
                                                
                                                function updateItem() {
                                                    if (item && item.item) {
                                                        item.item._appId = previewAppId
                                                        item.item._appName = previewAppName
                                                        item.item._appIcon = previewAppIcon
                                                        item.item.isPreviewMode = true
                                                    }
                                                }
                                                
                                                onLoaded: updateItem()
                                                onPreviewAppIdChanged: updateItem()
                                            }
                                            
                                            Loader {
                                                width: 720
                                                height: 1280
                                                active: model.type === "marathon" && model.appId === "settings"
                                                visible: status === Loader.Ready
                                                
                                                sourceComponent: (model.type === "marathon" && model.appId === "settings") ? settingsAppComponent : null
                                                
                                                onLoaded: {
                                                    if (item && item.item) {
                                                        item.item.isPreviewMode = true
                                                    }
                                                }
                                            }
                                            
                                            Loader {
                                                width: 720
                                                height: 1280
                                                active: model.type === "native"
                                                source: model.type === "native" ? "../apps/native/NativeAppWindow.qml" : ""
                                                visible: status === Loader.Ready
                                                
                                                onLoaded: {
                                                    if (item && model.surfaceId >= 0) {
                                                        item.surfaceId = model.surfaceId
                                                        item.nativeAppId = model.appId
                                                        item.nativeTitle = model.title
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                width: parent.width
                                height: Constants.touchTargetIndicator
                        color: Colors.surfaceLight
                                radius: 0
                                
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Constants.spacingSmall
                                    anchors.rightMargin: Constants.spacingSmall
                                    spacing: Constants.spacingSmall
                                    
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                source: model.icon
                                        width: 32
                                        height: 32
                                        fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
                                        smooth: true
                                sourceSize: Qt.size(32, 32)
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 80
                                        spacing: 2
                                        
                                        Text {
                                    text: model.title
                                            color: Colors.text
                                    font.pixelSize: Typography.sizeSmall
                                    font.weight: Font.DemiBold
                                            font.family: Typography.fontFamily
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        
                                        Text {
                                    text: model.subtitle || "Running"
                                            color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeXSmall
                                            font.family: Typography.fontFamily
                                    opacity: 0.7
                                        }
                                    }
                                    
                                    Item {
                                        id: closeButtonContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 32
                                        height: 32
                                        
                                        Rectangle {
                                            id: closeButtonRect
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
                                                id: closeButtonArea
                                                anchors.fill: parent
                                                anchors.margins: -8
                                                z: 1000
                                                preventStealing: true
                                                
                                                onPressed: (mouse) => {
                                                    cardDragArea.closeButtonClicked = true
                                                    mouse.accepted = true  // Block card drag area
                                                }
                                                
                                                onReleased: (mouse) => {
                                                    mouse.accepted = true  // Consume release
                                                }
                                                
                                                onClicked: (mouse) => {
                                                    Logger.info("TaskSwitcher", "Closing task via button: " + model.appId)
                                                    mouse.accepted = true  // Consume click
                                                    TaskModel.closeTask(model.id)
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
    
    // Vertical page indicator (shown when more than 4 apps)
    Column {
        id: pageIndicator
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingMedium
        visible: TaskModel.taskCount > 4
        z: 100  // Above cards
        
        property int pageCount: Math.ceil(TaskModel.taskCount / 4)
        property int currentPage: {
            // Calculate which page we're on based on contentY
            // Each page is exactly taskGrid.height tall (2 rows of cards)
            var page = Math.round(taskGrid.contentY / taskGrid.height)
            return Math.max(0, Math.min(page, pageCount - 1))
        }
        
        Repeater {
            model: pageIndicator.pageCount
            
            Rectangle {
                width: 6
                height: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? 32 : 16
                }
                radius: 3
                anchors.horizontalCenter: parent.horizontalCenter
                
                color: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? Colors.accent : Qt.rgba(255, 255, 255, 0.25)
                }
                
                border.width: 1
                border.color: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? Qt.rgba(20, 184, 166, 0.3) : Qt.rgba(255, 255, 255, 0.1)
                }
                
                layer.enabled: true
                
                Behavior on height {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                
                Behavior on color {
                    ColorAnimation {
                        duration: 250
                    }
                }
                
                Behavior on border.color {
                    ColorAnimation {
                        duration: 250
                    }
                }
            }
        }
    }
}
