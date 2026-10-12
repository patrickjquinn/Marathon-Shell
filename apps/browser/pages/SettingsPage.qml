pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Page {
    id: root

    property var browser
    readonly property alias homepageField: homepageField

    function commitHomepage() {
        if (!homepageField.visible)
            return;
        const url = Logic.homepageFromInput(homepageField.text);
        if (url && url !== browser.homepageUrl)
            browser.setHomepage(url);
    }

    objectName: "settingsPage"
    onStatusChanged: {
        if (status === PageStatus.Deactivating)
            commitHomepage();
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            TextSwitch {
                objectName: "privateSwitch"
                text: qsTr("Private browsing")
                description: qsTr("Don't save history or cookies")
                checked: root.browser.isPrivateMode
                automaticCheck: false
                onClicked: root.browser.setPrivateMode(!root.browser.isPrivateMode)
            }

            ComboBox {
                objectName: "searchEngineBox"
                label: qsTr("Search engine")
                currentIndex: Logic.indexOfName(Logic.searchEngines, root.browser.searchEngineName)
                menu: ContextMenu {
                    Repeater {
                        model: Logic.searchEngines

                        MenuItem {
                            required property var modelData

                            text: modelData.name
                            onClicked: root.browser.setSearchEngine(modelData.name, modelData.url)
                        }
                    }
                }
            }

            ComboBox {
                id: homepageBox

                objectName: "homepageBox"
                label: qsTr("Homepage")
                currentIndex: {
                    const i = Logic.indexOfUrl(Logic.homepages, root.browser.homepageUrl);
                    return i < 0 ? Logic.homepages.length : i;
                }
                menu: ContextMenu {
                    Repeater {
                        model: Logic.homepages

                        MenuItem {
                            required property var modelData

                            text: modelData.name
                            onClicked: root.browser.setHomepage(modelData.url)
                        }
                    }
                    MenuItem {
                        objectName: "customHomepageItem"
                        text: qsTr("Custom")
                    }
                }
            }

            TextField {
                id: homepageField

                objectName: "homepageField"
                width: parent.width
                visible: homepageBox.currentIndex === Logic.homepages.length
                label: qsTr("Homepage address")
                placeholderText: qsTr("Enter address")
                text: root.browser.homepageUrl
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: {
                    root.commitHomepage();
                    focus = false;
                }
            }

            SectionHeader {
                text: qsTr("Privacy")
            }

            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                Button {
                    objectName: "clearHistoryButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Clear history")
                    onClicked: remorse.execute(qsTr("Clearing history"), function () {
                        root.browser.clearHistory();
                    })
                }
                Button {
                    objectName: "clearCookiesButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Clear cookies and site data")
                    onClicked: remorse.execute(qsTr("Clearing cookies and site data"), function () {
                        root.browser.clearSiteData();
                    })
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    text: qsTr("Clearing cookies signs you out of most websites.")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
