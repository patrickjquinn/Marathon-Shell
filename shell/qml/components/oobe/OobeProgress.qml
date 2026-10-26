pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// A thin segmented bar: the steps so far lit, the rest faint.
Item {
    id: root

    property int count: 5
    // 1-based.
    property int current: 1

    implicitHeight: Silica.Theme.paddingLarge
    Accessible.role: Accessible.ProgressBar
    //: Setup progress, e.g. "Step 2 of 5"
    Accessible.name: qsTr("Step %1 of %2").arg(current).arg(count)

    Row {
        x: Silica.Theme.horizontalPageMargin
        width: parent.width - 2 * x
        anchors.verticalCenter: parent.verticalCenter
        spacing: Silica.Theme.paddingSmall

        Repeater {
            model: root.count

            Rectangle {
                required property int index

                width: (parent.width - (root.count - 1) * parent.spacing) / root.count
                height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
                radius: height / 2
                color: index < root.current ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.2)

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.durationFor("hover")
                    }
                }
            }
        }
    }
}
