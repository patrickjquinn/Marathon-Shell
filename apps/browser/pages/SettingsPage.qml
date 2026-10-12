pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Page {
    id: root

    property var browser
    readonly property alias homepageField: homepageField

    // false leaves the typed text in place, marked as an error.
    function commitHomepage() {
        if (!homepageField.visible)
            return true;
        const url = Logic.homepageFromInput(homepageField.text);
        homepageField.errorHighlight = url === "";
        if (url && url !== browser.homepageUrl)
            browser.setHomepage(url);
        return url !== "";
    }

    function clearBrowsingData() {
        const dialog = pageStack.push(Qt.resolvedUrl("ClearDataDialog.qml"));
        dialog.accepted.connect(function () {
            const history = dialog.history;
            const cookies = dialog.cookies;
            remorse.execute(qsTr("Cleared browsing data"), function () {
                if (history)
                    root.browser.clearHistory();
                if (cookies)
                    root.browser.clearSiteData();
            });
        });
    }

    objectName: "settingsPage"
    onStatusChanged: {
        if (status === PageStatus.Deactivating && !commitHomepage())
            Notices.show(qsTr("Homepage not changed. Enter a web address, like example.com"));
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
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

            ComboBox {
                id: homepageBox

                objectName: "homepageBox"
                label: qsTr("Home page")
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
                label: qsTr("Home page address")
                description: errorHighlight ? qsTr("Enter a web address, like example.com") : ""
                placeholderText: qsTr("Enter address")
                text: root.browser.homepageUrl
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: {
                    if (root.commitHomepage())
                        focus = false;
                }
                onTextChanged: errorHighlight = false
                onActiveFocusChanged: {
                    if (!activeFocus)
                        root.commitHomepage();
                }
            }

            ComboBox {
                objectName: "searchEngineBox"
                label: qsTr("Search on")
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

            SectionHeader {
                text: qsTr("Privacy")
            }

            TextSwitch {
                objectName: "privateSwitch"
                text: qsTr("Private browsing")
                description: qsTr("Don't save history or cookies")
                checked: root.browser.isPrivateMode
                automaticCheck: false
                onClicked: root.browser.setPrivateMode(!root.browser.isPrivateMode)
            }

            BackgroundItem {
                objectName: "clearDataItem"
                height: Theme.itemSizeSmall
                Accessible.name: clearLabel.text
                onClicked: root.clearBrowsingData()

                Label {
                    id: clearLabel

                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Clear browsing data")
                    truncationMode: TruncationMode.Fade
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
