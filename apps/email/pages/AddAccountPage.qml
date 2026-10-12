pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Page {
    id: page

    property var app
    readonly property var mail: app.mail
    property string statusText: ""
    property bool failed: false

    function signIn(provider) {
        failed = false;
        statusText = qsTr("Starting sign-in");
        if (!mail.startOAuthLogin(provider) && !failed) {
            failed = true;
            statusText = qsTr("Sign-in couldn't start. Try again, or use Other (IMAP).");
        }
    }

    Connections {
        target: page.mail
        ignoreUnknownSignals: true
        function onOauthAuthUrlReady(url) {
            page.failed = false;
            page.statusText = qsTr("Continue in your browser");
            Qt.openUrlExternally(url);
        }
        function onOauthLoginSucceeded(accountId) {
            page.statusText = "";
            page.app.showInbox();
        }
        function onOauthLoginFailed(code, message) {
            console.warn("Mail: OAuth login failed [" + code + "]: " + message);
            page.failed = true;
            page.statusText = Logic.oauthErrorText(code, message);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Add account")
            }

            Repeater {
                model: [
                    { id: "gmail", name: qsTr("Google") },
                    { id: "outlook", name: qsTr("Microsoft") },
                    { id: "imap", name: qsTr("Other (IMAP)") }
                ]

                ListItem {
                    id: provider

                    required property var modelData

                    objectName: "provider-" + modelData.id
                    contentHeight: Theme.itemSizeMedium
                    onClicked: {
                        if (modelData.id === "imap")
                            pageStack.push(Qt.resolvedUrl("MailAccountSetupPage.qml"), { app: page.app });
                        else
                            page.signIn(modelData.id);
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: provider.modelData.name
                        color: provider.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }

            Label {
                objectName: "status"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                visible: text !== ""
                text: page.statusText
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: page.failed ? Theme.errorColor : Theme.highlightColor
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                text: qsTr("Use Other (IMAP) for Fastmail, iCloud, Yahoo and any other provider.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }

        VerticalScrollDecorator {}
    }
}
