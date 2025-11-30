import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    color: MColors.background

    property string dialedNumber: ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.lg

        Item {
            Layout.preferredHeight: MSpacing.lg
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Constants.touchTargetLarge * 1.5
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing

            MLabel {
                anchors.centerIn: parent
                text: dialedNumber.length > 0 ? dialedNumber : "Dial a number"
                variant: dialedNumber.length > 0 ? "primary" : "secondary"
                font.pixelSize: MTypography.sizeXLarge
                font.family: MTypography.fontFamilyMono
            }
        }

        Item {
            Layout.preferredHeight: MSpacing.md
        }

        Grid {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width
            columns: 3
            columnSpacing: MSpacing.md
            rowSpacing: MSpacing.md

            Repeater {
                model: [
                    {
                        digit: "1",
                        letters: ""
                    },
                    {
                        digit: "2",
                        letters: "ABC"
                    },
                    {
                        digit: "3",
                        letters: "DEF"
                    },
                    {
                        digit: "4",
                        letters: "GHI"
                    },
                    {
                        digit: "5",
                        letters: "JKL"
                    },
                    {
                        digit: "6",
                        letters: "MNO"
                    },
                    {
                        digit: "7",
                        letters: "PQRS"
                    },
                    {
                        digit: "8",
                        letters: "TUV"
                    },
                    {
                        digit: "9",
                        letters: "WXYZ"
                    },
                    {
                        digit: "*",
                        letters: ""
                    },
                    {
                        digit: "0",
                        letters: "+"
                    },
                    {
                        digit: "#",
                        letters: ""
                    }
                ]

                Item {
                    required property var modelData
                    width: (parent.width - MSpacing.md * 2) / 3
                    height: Constants.touchTargetLarge

                    MCircularIconButton {
                        anchors.centerIn: parent
                        text: modelData.digit
                        buttonSize: Math.min(parent.width, parent.height) - 10
                        iconSize: 24
                        variant: "secondary"

                        // Show letters as subtitle if present
                        property string subtitle: modelData.letters

                        onClicked: {
                            HapticService.light();
                            if (modelData.digit === "0" && dialedNumber.length === 0) {
                                dialedNumber = "+";
                            } else {
                                dialedNumber += modelData.digit;
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width
            spacing: MSpacing.lg

            MIconButton {
                iconName: "delete"
                iconSize: 28
                variant: "secondary"
                disabled: dialedNumber.length === 0
                onClicked: {
                    if (dialedNumber.length > 0) {
                        dialedNumber = dialedNumber.slice(0, -1);
                    }
                }
            }

            MButton {
                text: "Call"
                iconName: "phone"
                iconLeft: true
                variant: "primary"
                size: "large"
                disabled: dialedNumber.length === 0
                implicitWidth: Constants.touchTargetLarge * 2
                onClicked: {
                    console.log("Calling:", dialedNumber);
                }
            }
        }
    }
}
