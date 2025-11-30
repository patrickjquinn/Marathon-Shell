import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: searchEnginePage
    color: MColors.background

    signal searchEngineSelected(string name, string url)
    signal backRequested

    property string currentSearchEngine: "Google"

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
                    color: backMouseArea.pressed ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

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
                            searchEnginePage.backRequested();
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search Engine"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.DemiBold
                    color: MColors.text
                }
            }
        }

        ListView {
            width: parent.width
            height: parent.height - (Constants.touchTargetMedium + MSpacing.md)
            clip: true
            spacing: 0

            model: ListModel {
                ListElement {
                    name: "Google"
                    url: "https://www.google.com/search?q="
                }
                ListElement {
                    name: "DuckDuckGo"
                    url: "https://duckduckgo.com/?q="
                }
                ListElement {
                    name: "Bing"
                    url: "https://www.bing.com/search?q="
                }
                ListElement {
                    name: "Brave Search"
                    url: "https://search.brave.com/search?q="
                }
                ListElement {
                    name: "Ecosia"
                    url: "https://www.ecosia.org/search?q="
                }
            }

            delegate: Rectangle {
                width: parent.width
                height: Constants.touchTargetLarge
                color: delegateMouseArea.pressed ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.lg
                    anchors.rightMargin: MSpacing.lg
                    spacing: MSpacing.md

                    Icon {
                        Layout.alignment: Qt.AlignVCenter
                        name: "search"
                        size: Constants.iconSizeSmall
                        color: MColors.textSecondary
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: model.name
                        font.pixelSize: MTypography.sizeBody
                        color: MColors.text
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                    }

                    Icon {
                        Layout.alignment: Qt.AlignVCenter
                        name: "check"
                        size: Constants.iconSizeSmall
                        color: MColors.accent
                        visible: model.name === searchEnginePage.currentSearchEngine
                    }
                }

                MouseArea {
                    id: delegateMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium();
                        searchEnginePage.searchEngineSelected(model.name, model.url);
                    }
                }
            }
        }
    }
}
