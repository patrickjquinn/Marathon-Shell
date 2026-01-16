import QtQuick
import QtQuick.Controls
import MarathonUI.Theme
import MarathonUI.Effects

SwipeView {
    id: root

    property bool hapticEnabled: true
    property bool bounceEnabled: true
    property real bounceIntensity: 0.1

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

    onMovingChanged: {
        if (moving) {
            swipeStarted();
        } else {
            swipeFinished();
        }
    }

    Behavior on contentItem.x {
        enabled: !moving
        SpringAnimation {
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
    }

    onContentItemChanged: {
        if (contentItem && bounceEnabled) {
            contentItem.boundsBehavior = Flickable.DragAndOvershootBounds;
        }
    }
}
