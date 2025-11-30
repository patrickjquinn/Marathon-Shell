import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: clipboardManager
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.95)
    visible: UIStore.clipboardManagerOpen
    z: 2650
    opacity: visible ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: UIStore.closeClipboardManager()
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight + 24
        anchors.leftMargin: Constants.spacingXLarge
        anchors.rightMargin: Constants.spacingXLarge
        anchors.bottomMargin: Constants.navBarHeight + 24
        spacing: Constants.spacingMedium

        Row {
            width: parent.width
            height: Constants.touchTargetMinimum

            Text {
                text: "Clipboard History"
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.DemiBold
                font.family: MTypography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: parent.width - 200
            }

            Rectangle {
                width: Math.round(80 * Constants.scaleFactor)
                height: Math.round(36 * Constants.scaleFactor)
                radius: Constants.borderRadiusSmall
                color: Qt.rgba(255, 255, 255, 0.08)
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(255, 255, 255, 0.12)

                Text {
                    text: "Clear"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        ClipboardService.clearHistory();
                        HapticService.light();
                    }
                }
            }
        }

        ListView {
            width: parent.width
            height: parent.height - 56
            clip: true
            spacing: Constants.spacingSmall

            model: ClipboardService.getHistory()

            delegate: Rectangle {
                width: ListView.view.width
                height: Constants.hubHeaderHeight
                radius: Constants.borderRadiusSmall
                color: Qt.rgba(255, 255, 255, 0.05)
                border.width: Constants.borderWidthThin
                border.color: itemMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.6) : Qt.rgba(255, 255, 255, 0.08)
                layer.enabled: true

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.03)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: Constants.spacingMedium

                    Column {
                        width: parent.width - Math.round(52 * Constants.scaleFactor)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.round(6 * Constants.scaleFactor)

                        Text {
                            text: modelData.text
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeBody
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }

                        Text {
                            text: {
                                var date = new Date(modelData.timestamp);
                                return Qt.formatDateTime(date, "hh:mm AP");
                            }
                            color: MColors.textTertiary
                            font.pixelSize: MTypography.sizeXSmall
                            font.family: MTypography.fontFamily
                        }
                    }

                    Rectangle {
                        width: Constants.touchTargetMinimum
                        height: Constants.touchTargetMinimum
                        radius: Constants.borderRadiusSmall
                        color: deleteMouseArea.pressed ? Qt.rgba(230, 57, 70, 0.2) : Qt.rgba(255, 255, 255, 0.05)
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Icon {
                            name: "trash-2"
                            size: Constants.iconSizeSmall
                            color: "#E63946"
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: deleteMouseArea
                            anchors.fill: parent
                            onClicked: {
                                ClipboardService.deleteItem(index);
                                HapticService.light();
                            }
                        }
                    }
                }

                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    anchors.rightMargin: Math.round(52 * Constants.scaleFactor)
                    onClicked: {
                        Logger.info("ClipboardManager", "Selected item: " + modelData.text.substring(0, 30));
                        ClipboardService.copyToClipboard(modelData.text);
                        HapticService.light();
                        UIStore.closeClipboardManager();
                    }
                }
            }

            Text {
                visible: parent.count === 0
                text: "No clipboard history"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                anchors.centerIn: parent
            }
        }
    }
}
