import QtQuick
import MarathonUI.Theme

// MEntrance — staggered entrance microinteraction for list/grid items.
//
// Drop into a delegate (or any Item whose first paint is a "reveal")
// to make it slide up + scale + fade in, with the stagger driven off
// `index`. Respects MMotion.reduceMotion: when off, the entrance
// becomes an instant opacity-only fade and the slide/scale collapse
// to a no-op.
//
// Tuning lives in MMotion.roles["entrance"] and MMotion.staggerShort.
//
// Usage (inside a ListView / Repeater delegate):
//   Rectangle {
//       id: row
//       width: parent.width
//       height: 56
//       MEntrance { target: row; index: model.index }
//       // ... row content
//   }
Item {
    id: ent

    property Item target: parent
    property int index: 0
    property int stagger: MMotion.staggerShort
    property real translateY: 8
    property real startScale: 0.96

    // The entrance only fires the first time the target becomes
    // visible. If it's already on-screen at construction we still want
    // the animation. Visibility-gating prevents the entrance running
    // on items that are scrolled into view later — for those, sets
    // the entrance trigger off and bind it to ListView.add transitions
    // higher up (cheaper than re-running entrances on every recycle).
    property bool playOnce: true
    property bool _played: false

    Component.onCompleted: {
        if (!target)
            return;
        if (MMotion.reduceMotion) {
            // Reduced-motion path: instant fade, no slide/scale.
            target.opacity = 0;
            target.scale = 1.0;
            fadeOnly.start();
            return;
        }
        target.opacity = 0;
        target.scale = startScale;
        target.y = (target.y || 0) + translateY;
        animator.start();
    }

    NumberAnimation {
        id: fadeOnly
        target: ent.target
        property: "opacity"
        from: 0
        to: 1
        duration: MMotion.dur(MMotion.fast)
        easing.type: Easing.OutQuad
        onStopped: ent._played = true
    }

    ParallelAnimation {
        id: animator

        PauseAnimation {
            duration: ent.index * ent.stagger
        }

        NumberAnimation {
            target: ent.target
            property: "opacity"
            from: 0
            to: 1
            duration: MMotion.durationFor("entrance")
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingCurveFor("entrance")
        }

        NumberAnimation {
            target: ent.target
            property: "scale"
            from: ent.startScale
            to: 1.0
            duration: MMotion.durationFor("entrance")
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingCurveFor("entrance")
        }

        NumberAnimation {
            target: ent.target
            property: "y"
            from: (ent.target ? ent.target.y : 0)
            to: (ent.target ? ent.target.y - ent.translateY : 0)
            duration: MMotion.durationFor("entrance")
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingCurveFor("entrance")
        }

        onStopped: ent._played = true
    }
}
