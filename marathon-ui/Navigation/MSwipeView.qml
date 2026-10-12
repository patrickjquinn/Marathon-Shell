import QtQuick
import QtQuick.Controls
import MarathonUI.Theme
import MarathonUI.Effects

SwipeView {
    id: root

    property bool hapticEnabled: true
    property bool bounceEnabled: true
    property real bounceIntensity: 0.1
    readonly property ListView listView: contentItem as ListView

    signal pageChanged(int index)
    signal swipeStarted
    signal swipeFinished

    clip: true

    interactive: true

    onCurrentIndexChanged: {
        if (hapticEnabled && MHaptics.enabled) {
            MHaptics.light();
        }
        pageChanged(currentIndex);
    }

    Connections {
        target: root.listView

        function onMovingChanged() {
            if (root.listView.moving)
                root.swipeStarted();
            else
                root.swipeFinished();
        }
    }

    Behavior on contentItem.x {
        enabled: !(root.listView && root.listView.moving)
        SpringAnimation {
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilonSpatial
        }
    }

    onContentItemChanged: {
        if (contentItem && bounceEnabled) {
            contentItem.boundsBehavior = Flickable.DragAndOvershootBounds;
        }
    }
}
