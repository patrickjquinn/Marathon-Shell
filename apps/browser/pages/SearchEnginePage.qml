pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: searchEnginePage

    property string currentSearchEngine: "Google"

    signal searchEngineSelected(string name, string url)
    signal backRequested

    function requestBack() {
        backRequested();
    }

    color: MColors.background

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
                    color: backMouseArea.pressed ? MColors.whiteOverlay10 : "transparent"

                    Accessible.role: Accessible.Button
                    Accessible.name: "Back"
                    Accessible.onPressAction: searchEnginePage.requestBack()

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
                            searchEnginePage.requestBack();
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
                id: engineDelegate

                required property string name
                required property string url

                width: parent.width
                height: Constants.touchTargetLarge
                color: delegateMouseArea.pressed ? MColors.whiteOverlay05 : "transparent"

                Accessible.role: Accessible.RadioButton
                Accessible.name: engineDelegate.name
                Accessible.checked: engineDelegate.name === searchEnginePage.currentSearchEngine
                Accessible.onPressAction: searchEnginePage.searchEngineSelected(engineDelegate.name, engineDelegate.url)

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
                        text: engineDelegate.name
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
                        visible: engineDelegate.name === searchEnginePage.currentSearchEngine
                    }
                }

                MouseArea {
                    id: delegateMouseArea

                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium();
                        searchEnginePage.searchEngineSelected(engineDelegate.name, engineDelegate.url);
                    }
                }
            }
        }
    }
}
