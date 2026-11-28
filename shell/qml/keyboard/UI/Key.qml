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
    property int selectedAlternate: -1
    property bool autoRepeat: false
    // Hold does something of its own, so release mustn't also click.
    property bool consumesHold: autoRepeat
    // The keyboard's touch layer drives the key; else its own MouseArea does.
    property bool routed: false
    readonly property bool isKeyboardKey: true
    readonly property bool isLetter: !isSpecial && text.length === 1 && text.toLowerCase() !== text.toUpperCase()
    property bool longPressTriggered: false
    // Where the finger is, in the key: the alternates are picked relative to it.
    property point pointer: Qt.point(width / 2, height / 2)
    property point holdPoint

    signal clicked
    signal pressAndHold

    // Function keys carry an identifier as their text; screen readers get a word.
    readonly property var _spokenNames: ({
            "shift": qsTr("Shift"),
            "backspace": qsTr("Backspace"),
            "dismiss": qsTr("Hide keyboard"),
            "emoji": qsTr("Emoji"),
            "enter": qsTr("Return"),
            " ": qsTr("Space")
        })
    Accessible.role: Accessible.Button
    Accessible.name: _spokenNames[key.text] || key.displayText || key.text
    Accessible.onPressAction: key.clicked()
    signal released
    signal alternateSelected(string character)

    width: Math.round(60 * Constants.scaleFactor)
    height: Math.round(45 * Constants.scaleFactor)
    // Letters without boxes, function keys on a faint
    // rounded backdrop, the ambience highlight under a pressed key.
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(Silica.Theme.paddingSmall / 2)
        radius: Silica.Theme.paddingSmall
        visible: key.pressed || key.isSpecial
        // On e-paper a grey the panel has, not a dither between two.
        color: key.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : MColors.eink ? MColors.controlFill : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.08)
    }

    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * Constants.scaleFactor)
        height: parent.height - Math.round(8 * Constants.scaleFactor)

        GlyphIcon {
            objectName: "keyGlyph"
            visible: key.iconName !== ""
            name: key.iconName
            size: Silica.Theme.iconSizeSmall
            color: key.pressed || key.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            anchors.centerIn: parent
        }

        Text {
            id: keyText

            visible: key.iconName === ""
            text: key.displayText
            color: key.pressed || key.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
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

        readonly property real padding: Math.round(Silica.Theme.paddingSmall / 2)
        property real popupWidth: key.alternateChars.length * key.width + 2 * padding
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
        anchors.bottomMargin: Math.round(Silica.Theme.paddingSmall / 2)

        sourceComponent: Rectangle {
            width: alternatePopup.popupWidth
            height: key.height + 2 * alternatePopup.padding
            radius: Silica.Theme.paddingMedium
            color: Qt.rgba(0, 0, 0, 0.9)

            Row {
                anchors.centerIn: parent

                Repeater {
                    model: key.alternateChars

                    Rectangle {
                        id: altKey

                        required property var modelData
                        required property int index
                        readonly property bool selected: index === key.selectedAlternate

                        objectName: "alternate_" + index
                        width: key.width
                        height: key.height
                        radius: Silica.Theme.paddingSmall
                        color: selected ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: altKey.modelData
                            color: altKey.selected ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                            font.family: Silica.Theme.fontFamily
                            font.pixelSize: Silica.Theme.fontSizeLarge
                        }
                    }
                }
            }
        }
    }

    function pointerPressed(x, y) {
        key.pointer = x === undefined ? Qt.point(key.width / 2, key.height / 2) : Qt.point(x, y);
        key.pressed = true;
        key.longPressTriggered = false;
        key.selectedAlternate = -1;
        if (SettingsManagerCpp.keyboardHapticStrength !== "off")
            HapticManager.light();
        longPressTimer.restart();
    }

    // A point in the key's own coordinates; it picks among the alternates.
    function pointerMoved(x, y) {
        key.pointer = Qt.point(x, y);
        if (!key.showingAlternates)
            return;
        if (key.selectedAlternate < 0 && Math.hypot(x - key.holdPoint.x, y - key.holdPoint.y) < Silica.Theme.startDragDistance)
            return;
        var i = Math.floor((x - alternatePopup.x - alternatePopup.padding) / key.width);
        key.selectedAlternate = Math.max(0, Math.min(key.alternateChars.length - 1, i));
    }

    function pointerReleased(commit) {
        longPressTimer.stop();
        repeatTimer.stop();
        key.pressed = false;
        if (key.showingAlternates) {
            if (key.selectedAlternate >= 0)
                key.alternateSelected(key.alternateChars[key.selectedAlternate]);
            else
                key.clicked();
        } else if (!(key.longPressTriggered && key.consumesHold) && commit) {
            key.clicked();
        }
        key.showingAlternates = false;
        key.selectedAlternate = -1;
        key.released();
    }

    function pointerCanceled() {
        longPressTimer.stop();
        repeatTimer.stop();
        key.pressed = false;
        key.showingAlternates = false;
        key.selectedAlternate = -1;
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: !key.routed
        onPressed: function (mouse) {
            key.pointerPressed(mouse.x, mouse.y);
            mouse.accepted = true;
        }
        onPositionChanged: function (mouse) {
            key.pointerMoved(mouse.x, mouse.y);
        }
        onReleased: function (mouse) {
            key.pointerReleased(containsMouse || key.showingAlternates);
            mouse.accepted = true;
        }
        onCanceled: key.pointerCanceled()
    }

    Timer {
        id: longPressTimer

        interval: 500
        repeat: false
        onTriggered: {
            key.longPressTriggered = true;
            if (key.alternateChars.length > 0) {
                if (SettingsManagerCpp.keyboardHapticStrength !== "off")
                    HapticManager.medium();
                key.holdPoint = key.pointer;
                key.showingAlternates = true;
            }
            key.pressAndHold();
            if (key.autoRepeat) {
                key.clicked();
                repeatTimer.start();
            }
        }
    }

    Timer {
        id: repeatTimer

        interval: 80
        repeat: true
        onTriggered: key.clicked()
    }

    Behavior on color {
        ColorAnimation {
            duration: MMotion.ms(50)
            easing.type: Easing.Linear
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: MMotion.ms(50)
            easing.type: Easing.OutCubic
        }
    }
}
