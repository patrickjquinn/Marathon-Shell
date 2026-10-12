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
    property bool waiting: false

    function signIn(provider) {
        failed = false;
        waiting = true;
        statusText = qsTr("Starting sign-in");
        if (!mail.startOAuthLogin(provider) && !failed) {
            waiting = false;
            failed = true;
            statusText = qsTr("Sign-in couldn't start. Try again, or use Other (IMAP).");
        }
    }

    Component.onCompleted: mail.checkOAuthProviders()
    Component.onDestruction: if (waiting)
        mail.cancelOAuthLogin()

    Connections {
        target: page.mail
        ignoreUnknownSignals: true
        function onOauthAuthUrlReady(url) {
            page.failed = false;
            page.statusText = qsTr("Continue in your browser");
            Qt.openUrlExternally(url);
        }
        function onOauthLoginSucceeded(accountId) {
            page.waiting = false;
            page.statusText = "";
            page.app.showInbox();
        }
        function onOauthLoginFailed(code, message) {
            page.waiting = false;
            if (code === "cancelled") {
                page.failed = false;
                page.statusText = "";
                return;
            }
            console.warn("Mail: OAuth login failed [" + code + "]: " + message);
            page.failed = true;
            page.statusText = Logic.oauthErrorText(code, message);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.waiting

            MenuItem {
                objectName: "cancelItem"
                text: qsTr("Cancel sign-in")
                onClicked: page.mail.cancelOAuthLogin()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Add account")
            }

            Repeater {
                // Google and Microsoft only when this build has their OAuth client.
                model: [
                    { id: "gmail", name: qsTr("Google") },
                    { id: "outlook", name: qsTr("Microsoft") },
                    { id: "imap", name: qsTr("Other (IMAP)") }
                ].filter(p => p.id === "imap" || page.mail.oauthProviders.indexOf(p.id) >= 0)

                ListItem {
                    id: provider

                    required property var modelData
                    readonly property bool needsNetwork: modelData.id !== "imap" && !page.mail.online

                    objectName: "provider-" + modelData.id
                    contentHeight: Theme.itemSizeMedium
                    enabled: !needsNetwork && !page.waiting
                    onClicked: {
                        if (modelData.id === "imap")
                            pageStack.push(Qt.resolvedUrl("MailAccountSetupPage.qml"), { app: page.app });
                        else
                            page.signIn(modelData.id);
                    }

                    Column {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: provider.enabled ? 1 : Theme.opacityLow

                        Label {
                            width: parent.width
                            text: provider.modelData.name
                            color: provider.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            objectName: "offlineNote"
                            width: parent.width
                            visible: provider.needsNetwork
                            text: qsTr("Needs an internet connection")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                        }
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
