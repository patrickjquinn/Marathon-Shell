pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Dialog {
    id: dialog

    property var mail
    property QtObject draftStore
    property string defaultTo: ""
    property string defaultCc: ""
    property string defaultSubject: ""
    property string defaultBody: ""
    // A new message picks up the saved draft; replies start from their prefill.
    property bool restoreDraft: false

    readonly property bool serviceReady: mail.accounts !== null && mail.currentAccountId !== ""
    readonly property var fields: ({
            to: toField.text,
            cc: ccField.text,
            subject: subjectField.text,
            body: bodyArea.text
        })
    property bool ready: false
    property bool edited: false

    function persistDraft() {
        draftStore.value = Logic.draft(fields);
    }

    canAccept: serviceReady && toField.text.trim() !== ""
    onFieldsChanged: {
        if (!ready)
            return;
        edited = true;
        autosave.restart();
    }
    onAcceptBlocked: Notices.show(serviceReady ? qsTr("Add a recipient first") : qsTr("Add a mail account before sending"))
    onAccepted: {
        autosave.stop();
        if (mail.send(toField.text.trim(), ccField.text.trim(), subjectField.text, bodyArea.text, [])) {
            draftStore.value = "";
            Notices.show(qsTr("Sending message"));
        } else {
            persistDraft();
            Notices.show(qsTr("Your message wasn't sent. It's saved as a draft."));
        }
    }
    onRejected: {
        autosave.stop();
        if (!edited)
            return;
        persistDraft();
        if (draftStore.value !== "")
            Notices.show(qsTr("Draft saved"));
    }
    Component.onCompleted: {
        const d = restoreDraft ? Logic.parseDraft(draftStore.value) : null;
        if (d) {
            toField.text = d.to;
            ccField.text = d.cc;
            subjectField.text = d.subject;
            bodyArea.text = d.body;
        }
        ready = true;
    }

    Timer {
        id: autosave

        interval: 2000
        onTriggered: dialog.persistDraft()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Send")
                title: /^fwd:/i.test(dialog.defaultSubject) ? qsTr("Forward") : /^re:/i.test(dialog.defaultSubject) ? qsTr("Reply") : qsTr("New message")
            }
            Label {
                objectName: "serviceNotice"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                visible: !dialog.serviceReady
                text: dialog.mail.accounts === null ? qsTr("Mail isn't available right now. Close Mail and open it again.") : qsTr("Add a mail account before sending. Go back to the inbox to sign in.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.errorColor
            }
            DetailItem {
                objectName: "fromItem"
                visible: dialog.serviceReady
                label: qsTr("From")
                value: dialog.mail.currentAccountName
                alignment: Qt.AlignLeft
            }
            TextField {
                id: toField

                objectName: "toField"
                width: parent.width
                enabled: dialog.serviceReady
                label: qsTr("To")
                placeholderText: qsTr("To")
                text: dialog.defaultTo
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: ccField.focus = true
            }
            TextField {
                id: ccField

                objectName: "ccField"
                width: parent.width
                enabled: dialog.serviceReady
                label: qsTr("Cc")
                placeholderText: qsTr("Cc")
                text: dialog.defaultCc
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: subjectField.focus = true
            }
            TextField {
                id: subjectField

                objectName: "subjectField"
                width: parent.width
                enabled: dialog.serviceReady
                label: qsTr("Subject")
                placeholderText: qsTr("Subject")
                text: dialog.defaultSubject
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: bodyArea.focus = true
            }
            TextArea {
                id: bodyArea

                objectName: "bodyArea"
                width: parent.width
                enabled: dialog.serviceReady
                placeholderText: qsTr("Message")
                text: dialog.defaultBody
            }
        }

        VerticalScrollDecorator {}
    }
}
