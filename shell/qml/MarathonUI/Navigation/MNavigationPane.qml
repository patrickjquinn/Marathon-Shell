import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme

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
            ParallelAnimation {
                // Incoming page: slide from right with slight scale
                NumberAnimation {
                    property: "x"
                    from: stackView.width
                    to: 0
                    duration: MMotion.moderate
                    easing.type: MMotion.easingEmphasized
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.95
                    to: 1.0
                    duration: MMotion.moderate
                    easing.type: MMotion.easingDecelerate
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: MMotion.quick
                }
            }
        }
        
        pushExit: Transition {
            ParallelAnimation {
                // Outgoing page: parallax shift left + scale down + fade
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -stackView.width * MMotion.pageParallaxOffset
                    duration: MMotion.moderate
                    easing.type: MMotion.easingEmphasized
                }
                NumberAnimation {
                    property: "scale"
                    from: 1.0
                    to: MMotion.pageScaleOut
                    duration: MMotion.moderate
                    easing.type: MMotion.easingAccelerate
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.3
                    duration: MMotion.moderate
                }
            }
        }
        
        popEnter: Transition {
            ParallelAnimation {
                // Returning page: parallax shift right + scale up + fade in
                NumberAnimation {
                    property: "x"
                    from: -stackView.width * MMotion.pageParallaxOffset
                    to: 0
                    duration: MMotion.moderate
                    easing.type: MMotion.easingEmphasized
                }
                NumberAnimation {
                    property: "scale"
                    from: MMotion.pageScaleOut
                    to: 1.0
                    duration: MMotion.moderate
                    easing.type: MMotion.easingDecelerate
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.3
                    to: 1
                    duration: MMotion.moderate
                }
            }
        }
        
        popExit: Transition {
            ParallelAnimation {
                // Exiting page: slide right + fade out
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: stackView.width
                    duration: MMotion.moderate
                    easing.type: MMotion.easingEmphasized
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: MMotion.quick
                }
            }
        }
        
        replaceEnter: pushEnter
        replaceExit: pushExit
    }
    
    function push(page, properties) {
        var result = stackView.push(page, properties || {})
        pagePushed(result)
        return result
    }
    
    function pop() {
        var result = stackView.pop()
        pagePopped(result)
        return result
    }
    
    function popToRoot() {
        while (stackView.depth > 1) {
            stackView.pop()
        }
    }
    
    function replace(page, properties) {
        return stackView.replace(page, properties || {})
    }
    
    function clear() {
        stackView.clear()
    }
}

