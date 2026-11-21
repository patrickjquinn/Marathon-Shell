// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A row of the page menu, as the Sailfish Browser's menu rows: an icon in
// a fixed column, the label, and for an option that is on or off a Silica
// Switch at the end.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: button

    property alias iconSource: icon.source
    property alias text: label.text
    property bool checkable
    property bool checked

    width: parent ? parent.width : implicitWidth
    implicitWidth: label.anchors.leftMargin + label.implicitWidth + (checkable ? toggle.width + toggle.anchors.rightMargin : Theme.horizontalPageMargin)
    height: Theme.itemSizeSmall
    opacity: enabled ? 1.0 : Theme.opacityLow

    Icon {
        id: icon
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        highlighted: button.highlighted
    }
    Label {
        id: label
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin + Theme.iconSizeMedium + Theme.paddingLarge
            right: toggle.visible ? toggle.left : parent.right
            rightMargin: toggle.visible ? 0 : Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        truncationMode: TruncationMode.Fade
        color: button.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
    Switch {
        id: toggle
        visible: button.checkable
        anchors {
            right: parent.right
            rightMargin: Theme.paddingSmall
            verticalCenter: parent.verticalCenter
        }
        checked: button.checked
        automaticCheck: false
        onClicked: button.clicked(null)
    }
}
