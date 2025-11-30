import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: homepagePage
    color: MColors.background

    signal homepageChanged(string url)
    signal backRequested

    property string currentHomepage: "https://www.google.com"

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            width: parent.width
            height: Constants.touchTargetMedium + MSpacing.md
            color: MColors.surface

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.md

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.touchTargetSmall
                    height: Constants.touchTargetSmall
                    radius: Constants.borderRadiusSmall
                    color: backMouseArea.pressed ? MColors.highlightSubtle : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        name: "chevron-left"
                        size: Constants.iconSizeSmall
                        color: MColors.text
                    }

                    MouseArea {
                        id: backMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            homepagePage.backRequested();
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Homepage"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.DemiBold
                    color: MColors.text
                }
            }
        }

        Column {
            width: parent.width
            spacing: 0

            ListView {
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: 0

                model: ListModel {
                    ListElement {
                        name: "Google"
                        url: "https://www.google.com"
                    }
                    ListElement {
                        name: "DuckDuckGo"
                        url: "https://duckduckgo.com"
                    }
                    ListElement {
                        name: "Bing"
                        url: "https://www.bing.com"
                    }
                    ListElement {
                        name: "Blank Page"
                        url: "about:blank"
                    }
                }

                delegate: Rectangle {
                    width: parent.width
                    height: Constants.touchTargetLarge
                    color: delegateMouseArea.pressed ? MColors.highlightSubtle : "transparent"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Constants.borderWidthThin
                        color: MColors.border
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.lg
                        anchors.rightMargin: MSpacing.lg
                        spacing: MSpacing.md

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "home"
                            size: Constants.iconSizeSmall
                            color: MColors.textSecondary
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.spacing * 2 - parent.children[0].width - parent.children[2].width - MSpacing.md
                            spacing: 2

                            Text {
                                width: parent.width
                                text: model.name
                                font.pixelSize: MTypography.sizeBody
                                color: MColors.text
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: model.url
                                font.pixelSize: MTypography.sizeSmall
                                color: MColors.textTertiary
                                elide: Text.ElideMiddle
                            }
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: Constants.iconSizeSmall
                            color: MColors.accent
                            visible: model.url === homepagePage.currentHomepage
                        }
                    }

                    MouseArea {
                        id: delegateMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            homepagePage.homepageChanged(model.url);
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: MSpacing.lg + Constants.touchTargetLarge + MSpacing.sm
                color: MColors.surface

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: MSpacing.lg
                    spacing: MSpacing.sm

                    Text {
                        text: "Custom Homepage"
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        color: MColors.textSecondary
                    }

                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: MColors.elevated
                        border.width: Constants.borderWidthThin
                        border.color: customUrlInput.activeFocus ? MColors.accent : MColors.border

                        TextInput {
                            id: customUrlInput
                            anchors.fill: parent
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.md
                            verticalAlignment: TextInput.AlignVCenter
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.family: MTypography.fontFamily
                            selectByMouse: true
                            selectedTextColor: MColors.background
                            selectionColor: MColors.accent
                            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                            text: homepagePage.currentHomepage

                            onAccepted: {
                                HapticService.medium();
                                if (text.length > 0) {
                                    homepagePage.homepageChanged(text);
                                }
                                focus = false;
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !customUrlInput.text && !customUrlInput.activeFocus
                                text: "Enter custom URL"
                                color: MColors.textTertiary
                                font.pixelSize: MTypography.sizeBody
                                font.family: MTypography.fontFamily
                            }
                        }
                    }
                }
            }
        }
    }
}
