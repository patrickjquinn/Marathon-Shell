import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

// MPressable — the press primitive of the Marathon DS.
//
// Wraps any tappable surface that isn't already an M-button (rows,
// chips, app icons, gallery thumbs, dock items, custom widgets). The
// caller places content inside MPressable; on press it scales itself
// with the canonical microPress spring from MMotion, on release it
// rebounds. Haptic feedback is routed through MHaptics, gated on the
// `haptic` enum, defaulting to a light click (iOS-row feel).
//
// Why a primitive instead of inline MouseArea + ad-hoc Behaviors:
// every press surface should feel identical. Centralising the scale
// curve, spring stiffness, and haptic intensity here means tuning
// the system's feel is one file, not 200 call sites.
//
// Cost: one MouseArea + one Behavior on scale. Compositor-only path
// (scale change does not force layout).
//
// Usage:
//   MPressable {
//       width: parent.width
//       height: 56
//       onClicked: ApplicationManager.launch(app.id)
//       Rectangle {
//           anchors.fill: parent
//           color: parent.pressed ? MColors.highlightSubtle : "transparent"
//           // ... rest of the row
//       }
//   }
Item {
    id: pressable

    default property alias content: contentContainer.data

    property real pressScale: 0.97
    property string haptic: "light"
    property bool clickable: true
    property bool visualFeedback: true
    property alias hoverEnabled: ma.hoverEnabled
    property alias preventStealing: ma.preventStealing
    property alias acceptedButtons: ma.acceptedButtons
    property alias pressed: ma.pressed
    property alias containsMouse: ma.containsMouse

    signal clicked(var mouse)
    signal pressAndHold(var mouse)
    signal doubleClicked(var mouse)

    // Visual-feedback transform origin lives at the centre. Callers
    // that need top-anchored items (a card scaling off its title bar)
    // expose transformOrigin via property override.
    transformOrigin: Item.Center

    Item {
        id: contentContainer
        anchors.fill: parent
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: pressable.clickable
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton

        onPressed: function (mouse) {
            if (pressable.visualFeedback)
                pressable.scale = pressable.pressScale;
        }
        onReleased: function (mouse) {
            if (pressable.visualFeedback)
                pressable.scale = 1.0;
        }
        onCanceled: {
            if (pressable.visualFeedback)
                pressable.scale = 1.0;
        }
        onClicked: function (mouse) {
            if (pressable.haptic === "light")
                MHaptics.lightImpact();
            else if (pressable.haptic === "medium")
                MHaptics.mediumImpact();
            else if (pressable.haptic === "heavy")
                MHaptics.heavyImpact();
            pressable.clicked(mouse);
        }
        onPressAndHold: function (mouse) {
            pressable.pressAndHold(mouse);
        }
        onDoubleClicked: function (mouse) {
            pressable.doubleClicked(mouse);
        }
    }

    Behavior on scale {
        enabled: pressable.visualFeedback && !MMotion.reduceMotion
        SpringAnimation {
            spring: MMotion.springFor("microPress")
            damping: MMotion.dampingFor("microPress")
            epsilon: MMotion.epsilon
        }
    }
}
