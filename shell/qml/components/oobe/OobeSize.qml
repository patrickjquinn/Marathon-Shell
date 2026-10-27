import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../../core/Scales.js" as Scales

// Easy to read: text and icon size, on the real home grid.
Item {
    id: root

    signal done

    // Return continues, unless something inside the beat (a field) has the keys.
    function continueOnReturn(event) {
        event.accepted = activeFocus;
        if (activeFocus)
            done();
    }

    Keys.onReturnPressed: event => continueOnReturn(event)
    Keys.onEnterPressed: event => continueOnReturn(event)
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }

    function applySize() {
        settle.stop();
        const factor = Scales.factors[Math.round(slider.value)];
        if (Math.abs(factor - SettingsManagerCpp.userScaleFactor) > 0.001)
            SettingsManagerCpp.userScaleFactor = factor;
    }

    // Re-sizing the whole shell takes longer than a drag step on small
    // devices, so the size follows when the finger rests or lifts.
    Timer {
        id: settle

        interval: 250
        onTriggered: root.applySize()
    }

    Column {
        id: column

        // On a short screen at a large size the hint and gaps give way so
        // one whole row of the preview still shows.
        readonly property bool roomy: height - heading.height - hint.implicitHeight - slider.height - button.height - 4 * Silica.Theme.paddingMedium >= preview.oneRowHeight

        anchors.fill: parent
        anchors.topMargin: Silica.Theme.paddingLarge
        anchors.bottomMargin: Silica.Theme.paddingMedium
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        spacing: roomy ? Silica.Theme.paddingMedium : Silica.Theme.paddingSmall

        Silica.Label {
            id: heading

            width: parent.width
            text: qsTr("Easy to read")
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
            wrapMode: Text.WordWrap
        }

        Silica.Label {
            id: hint

            width: parent.width
            visible: column.roomy
            //: Setup, size step: what the slider does
            text: qsTr("Drag until your home screen feels right.")
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        OobeGridPreview {
            id: preview

            objectName: "sizePreview"
            width: parent.width
            height: Math.max(0, parent.height - y - slider.height - button.height - 2 * parent.spacing)
            rows: fitRows
        }

        Silica.Slider {
            id: slider

            objectName: "sizeSlider"
            width: parent.width
            label: qsTr("Text and icon size")
            minimumValue: 0
            maximumValue: Scales.factors.length - 1
            stepSize: 1
            value: Scales.nearest(SettingsManagerCpp.userScaleFactor)
            valueText: Scales.label(value)
            onValueChanged: {
                if (down)
                    settle.restart();
            }
            onDownChanged: {
                if (!down)
                    root.applySize();
            }
        }

        Silica.Button {
            id: button

            objectName: "sizeContinue"

            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Continue")
            onClicked: root.done()
        }
    }
}
