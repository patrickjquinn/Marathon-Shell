import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Item {
    id: root
    
    property real value: 0.5
    property real from: 0.0
    property real to: 1.0
    property bool disabled: false
    
    signal moved()
    signal released()
    
    readonly property alias pressed: handleArea.pressed
    
    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real trackHeight: Math.max(1, Math.round(4 * scaleFactor))
    readonly property real trackRadius: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real handleWidth: Math.round(28 * scaleFactor)
    readonly property real handleHeight: Math.round(28 * scaleFactor)
    readonly property real handleRadius: handleWidth / 2
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderWidthThick: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real handleInnerMargin: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real touchTargetSize: Math.round(44 * scaleFactor)
    readonly property real touchTargetOffset: Math.max(1, Math.round(8 * scaleFactor))
    
    implicitWidth: parent ? parent.width : 240
    implicitHeight: MSpacing.touchTargetMin
    
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: trackHeight
        radius: trackRadius
        color: MColors.bb10Surface
        border.width: borderWidth
        border.color: MColors.borderGlass
        
        Rectangle {
            width: (root.value - root.from) / (root.to - root.from) * parent.width
            height: parent.height
            radius: parent.radius
            color: MColors.marathonTeal
        }
    }
    
    Rectangle {
        id: handle
        x: (root.value - root.from) / (root.to - root.from) * (parent.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: handleWidth
        height: handleHeight
        radius: handleRadius
        color: MColors.textPrimary
        border.width: borderWidthThick
        border.color: MColors.marathonTeal
        scale: handleArea.pressed ? 1.15 : 1.0
        
        Behavior on scale {
            SpringAnimation { 
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }
        
        Behavior on x {
            enabled: !handleArea.drag.active
            NumberAnimation { duration: MMotion.quick }
        }
        
        // Inner highlight
        Rectangle {
            anchors.fill: parent
            anchors.margins: handleInnerMargin
            radius: parent.radius > handleInnerMargin ? parent.radius - handleInnerMargin : 0
            color: "transparent"
            border.width: borderWidth
            border.color: Qt.rgba(1, 1, 1, 0.3)
        }
    }
    
    // Extended touch target for easier grabbing
    Rectangle {
        id: touchTarget
        x: handle.x - touchTargetOffset
        anchors.verticalCenter: parent.verticalCenter
        width: touchTargetSize
        height: touchTargetSize
        color: "transparent"  // Invisible
    }
    
    MouseArea {
        id: handleArea
        anchors.fill: parent
        enabled: !disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        
        drag.target: handle
        drag.axis: Drag.XAxis
        drag.minimumX: 0
        drag.maximumX: root.width - handle.width
        
        onPressed: function(mouse) {
            var newX = Math.max(0, Math.min(mouse.x - handle.width / 2, root.width - handle.width))
            handle.x = newX
            updateValue()
        }
        
        onReleased: root.released()
        
        onPositionChanged: {
            if (drag.active) {
                updateValue()
            }
        }
        
        function updateValue() {
            var ratio = handle.x / (root.width - handle.width)
            root.value = root.from + ratio * (root.to - root.from)
            root.moved()
        }
    }
}

