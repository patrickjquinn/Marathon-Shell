import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    id: root
    
    property Component initialPage: null
    property alias currentPage: stackView.currentItem
    property int depth: stackView.depth
    
    signal pagePopped(var page)
    signal pagePushed(var page)
    
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: root.initialPage
        
        pushEnter: Transition {
            PropertyAnimation {
                property: "x"
                from: stackView.width
                to: 0
                duration: Constants.animationNormal
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Constants.animationNormal
            }
        }
        
        pushExit: Transition {
            PropertyAnimation {
                property: "x"
                from: 0
                to: -stackView.width * 0.3
                duration: Constants.animationNormal
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                property: "opacity"
                from: 1
                to: 0.5
                duration: Constants.animationNormal
            }
        }
        
        popEnter: Transition {
            PropertyAnimation {
                property: "x"
                from: -stackView.width * 0.3
                to: 0
                duration: Constants.animationNormal
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                property: "opacity"
                from: 0.5
                to: 1
                duration: Constants.animationNormal
            }
        }
        
        popExit: Transition {
            PropertyAnimation {
                property: "x"
                from: 0
                to: stackView.width
                duration: Constants.animationNormal
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: Constants.animationNormal
            }
        }
        
        onCurrentItemChanged: {
            if (currentItem && currentItem.title) {
                // Auto-update action bar title if present
            }
        }
    }
    
    function push(page, properties) {
        var item = stackView.push(page, properties)
        root.pagePushed(item)
        return item
    }
    
    function pop() {
        var item = stackView.pop()
        root.pagePopped(item)
        return item
    }
    
    function popToRoot() {
        while (stackView.depth > 1) {
            stackView.pop()
        }
    }
    
    function clear() {
        stackView.clear()
    }
}

