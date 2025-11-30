import QtQuick
import QtQuick.Controls
import MarathonUI.Theme
import MarathonUI.Effects

SwipeView {
    id: root

    // Custom properties
    property bool hapticEnabled: true
    property bool bounceEnabled: true
    property real bounceIntensity: 0.1

    // Signals
    signal pageChanged(int index)
    signal swipeStarted
    signal swipeFinished

    clip: true

    // Spring physics for page transitions
    interactive: true

    // Haptic feedback on page change
    onCurrentIndexChanged: {
        if (hapticEnabled && MHaptics.enabled) {
            MHaptics.light();
        }
        pageChanged(currentIndex);
    }

    // Track swipe state
    onMovingChanged: {
        if (moving) {
            swipeStarted();
        } else {
            swipeFinished();
        }
    }

    // Custom page transition with spring physics
    Behavior on contentItem.x {
        enabled: !moving
        SpringAnimation {
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
    }

    // Rubber-band overscroll effect
    onContentItemChanged: {
        if (contentItem && bounceEnabled) {
            contentItem.boundsBehavior = Flickable.DragAndOvershootBounds;
        }
    }
}
