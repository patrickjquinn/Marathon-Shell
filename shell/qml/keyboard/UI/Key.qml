pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Rectangle {
    id: key

    property string text: ""
    property string displayText: text
    property string alternateText: ""
    property var alternateChars: []
    property bool isSpecial: false
    property string iconName: ""
    property int keyCode: Qt.Key_unknown
    property alias fontFamily: keyText.font.family
    property bool pressed: false
    property bool highlighted: false
    property bool showingAlternates: false
    property real cachedTextWidth: 0
    property real cachedTextHeight: 0

    signal clicked
    signal pressAndHold
    signal released
    signal alternateSelected(string character)

    width: Math.round(60 * Constants.scaleFactor)
    height: Math.round(45 * Constants.scaleFactor)
    // Sailfish's keyboard: letters without boxes, function keys on a faint
    // rounded backdrop, the ambience highlight under a pressed key.
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(Silica.Theme.paddingSmall / 2)
        radius: Silica.Theme.paddingSmall
        visible: key.pressed || key.isSpecial
        color: key.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
                           : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.08)
    }

    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * Constants.scaleFactor)
        height: parent.height - Math.round(8 * Constants.scaleFactor)

        GlyphIcon {
            visible: key.iconName !== ""
            name: key.iconName
            size: Silica.Theme.iconSizeSmall
            color: key.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            anchors.centerIn: parent
        }

        Text {
            id: keyText

            visible: key.iconName === ""
            text: key.displayText
            color: key.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: key.isSpecial ? Silica.Theme.fontSizeSmall : Silica.Theme.fontSizeLarge
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.centerIn: parent
        }

        Text {
            visible: key.alternateText !== "" && !key.pressed
            text: key.alternateText
            color: Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeTiny
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(2 * Constants.scaleFactor)
        }
    }

    Rectangle {
        id: preview

        visible: key.pressed && !key.isSpecial && !key.showingAlternates
        width: Math.round(70 * Constants.scaleFactor)
        height: Math.round(80 * Constants.scaleFactor)
        x: (parent.width - width) / 2
        y: -height - Math.round(10 * Constants.scaleFactor)
        z: 1000
        radius: Silica.Theme.paddingMedium
        color: Qt.rgba(0, 0, 0, 0.9)

        Text {
            text: key.displayText
            color: Silica.Theme.highlightColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeHuge
            anchors.centerIn: parent
        }
    }

    Loader {
        id: alternatePopup

        property real popupWidth: Math.round((60 * key.alternateChars.length + 4 * (key.alternateChars.length - 1)) * Constants.scaleFactor)
        property real keyGlobalX: key.mapToItem(null, 0, 0).x
        property real screenWidth: Constants.screenWidth

        active: key.showingAlternates && key.alternateChars.length > 0
        z: 2000
        x: {
            var centerX = (key.width - popupWidth) / 2;
            var leftEdge = keyGlobalX + centerX;
            var rightEdge = leftEdge + popupWidth;
            if (leftEdge < 0)
                return -keyGlobalX;
            else if (rightEdge > screenWidth)
                return screenWidth - keyGlobalX - popupWidth;
            else
                return centerX;
        }
        anchors.bottom: parent.top
        anchors.bottomMargin: Math.round(8 * Constants.scaleFactor)

        sourceComponent: Rectangle {
            width: alternatePopup.popupWidth
            height: Math.round(50 * Constants.scaleFactor)
            radius: Silica.Theme.paddingMedium
            color: Qt.rgba(0, 0, 0, 0.9)

            Row {
                anchors.centerIn: parent
                spacing: Math.round(4 * Constants.scaleFactor)

                Repeater {
                    model: key.alternateChars

                    Rectangle {
                        id: altKey

                        required property var modelData

                        width: Math.round(50 * Constants.scaleFactor)
                        height: Math.round(40 * Constants.scaleFactor)
                        radius: Silica.Theme.paddingSmall
                        color: altMouseArea.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: altKey.modelData
                            color: altMouseArea.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                            font.family: Silica.Theme.fontFamily
                            font.pixelSize: Silica.Theme.fontSizeLarge
                        }

                        MouseArea {
                            id: altMouseArea

                            anchors.fill: parent
                            onClicked: {
                                HapticManager.light();
                                key.alternateSelected(altKey.modelData);
                                key.showingAlternates = false;
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea

        property bool longPressTriggered: false

        anchors.fill: parent
        onPressed: function (mouse) {
            key.pressed = true;
            longPressTriggered = false;
            HapticManager.light();
            if (key.alternateChars.length > 0)
                longPressTimer.restart();

            mouse.accepted = true;
        }
        onReleased: function (mouse) {
            longPressTimer.stop();
            key.pressed = false;
            if (!longPressTriggered && containsMouse) {
                if (!key.showingAlternates)
                    key.clicked();
            }
            key.showingAlternates = false;
            key.released();
            mouse.accepted = true;
        }
        onCanceled: {
            longPressTimer.stop();
            key.pressed = false;
            key.showingAlternates = false;
        }
    }

    Timer {
        id: longPressTimer

        interval: 500
        repeat: false
        onTriggered: {
            if (key.alternateChars.length > 0) {
                HapticManager.medium();
                key.showingAlternates = true;
                mouseArea.longPressTriggered = true;
                key.pressAndHold();
            }
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 50
            easing.type: Easing.Linear
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 50
            easing.type: Easing.OutCubic
        }
    }
}
