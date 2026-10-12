pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

DockedPanel {
    id: panel

    property QtObject camera
    readonly property var timers: [0, 3, 10]

    function resolutionIndex() {
        const want = camera.photoResolution;
        if (!want || want.width <= 0)
            return 0;
        const list = camera.photoResolutions;
        for (let i = 0; i < list.length; ++i) {
            if (list[i].width === want.width && list[i].height === want.height)
                return i + 1;
        }
        return 0;
    }

    function resolutionText(size) {
        return qsTr("%1 × %2 (%3 MP)").arg(size.width).arg(size.height).arg((size.width * size.height / 1e6).toFixed(1));
    }

    // ComboBox overwrites a plain currentIndex binding when it loads its menu.
    Binding {
        target: timerCombo
        property: "currentIndex"
        value: Math.max(0, panel.timers.indexOf(panel.camera.timerDuration))
    }

    Binding {
        target: resolutionCombo
        property: "currentIndex"
        value: panel.resolutionIndex()
    }

    dock: Dock.Top
    modal: true
    width: parent ? parent.width : 0
    height: Math.min(content.height, parent ? parent.height : content.height)
    contentHeight: content.height
    background: Rectangle {
        color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityOverlay)
    }

    Column {
        id: content

        width: parent.width
        bottomPadding: Theme.paddingLarge

        SectionHeader {
            text: qsTr("Camera settings")
        }

        TextSwitch {
            objectName: "flashSwitch"
            text: qsTr("Flash")
            description: panel.camera.flashAvailable ? "" : qsTr("This camera has no flash")
            enabled: panel.camera.flashAvailable
            automaticCheck: false
            checked: panel.camera.flashEnabled
            onClicked: panel.camera.flashEnabled = !panel.camera.flashEnabled
        }

        ComboBox {
            id: timerCombo

            objectName: "timerCombo"
            label: qsTr("Self-timer")
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Off")
                    onClicked: panel.camera.timerDuration = 0
                }
                MenuItem {
                    text: qsTr("3 seconds")
                    onClicked: panel.camera.timerDuration = 3
                }
                MenuItem {
                    text: qsTr("10 seconds")
                    onClicked: panel.camera.timerDuration = 10
                }
            }
        }

        ComboBox {
            id: resolutionCombo

            objectName: "resolutionCombo"
            label: qsTr("Photo resolution")
            visible: panel.camera.photoResolutions.length > 0
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Automatic")
                    onClicked: panel.camera.photoResolution = Qt.size(-1, -1)
                }
                Repeater {
                    model: panel.camera.photoResolutions

                    MenuItem {
                        required property var modelData

                        text: panel.resolutionText(modelData)
                        onClicked: panel.camera.photoResolution = modelData
                    }
                }
            }
        }

        DetailItem {
            label: qsTr("Camera")
            value: panel.camera.currentCameraName || qsTr("None")
        }

        DetailItem {
            label: qsTr("Saved to")
            value: qsTr("Pictures/Marathon")
        }
    }
}
