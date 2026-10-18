pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Dialog {
    id: dialog

    property var mail
    property var draftStore
    property string draftKey
    property string defaultTo: ""
    property string defaultCc: ""
    property string defaultSubject: ""
    property string defaultBody: ""

    readonly property bool serviceReady: mail.accounts !== null && mail.currentAccountId !== ""
    readonly property var fields: ({
            to: toField.text,
            cc: ccField.text,
            bcc: bccField.text,
            subject: subjectField.text,
            body: bodyArea.text
        })
    readonly property var to: Logic.parseRecipients(toField.text)
    readonly property var cc: Logic.parseRecipients(ccField.text)
    readonly property var bcc: Logic.parseRecipients(bccField.text)
    readonly property string invalid: to.invalid || cc.invalid || bcc.invalid
    property bool ready: false
    property bool edited: false
    property bool showCopies: defaultCc !== ""
    // Set once an accept is blocked, so errors also show in the focused field.
    property bool showErrors: false

    function persistDraft() {
        draftStore.value = Logic.withDraft(draftStore.value, draftKey, fields, Date.now());
    }

    function invalidText(result) {
        return result.invalid !== "" ? qsTr("“%1” isn't an email address").arg(result.invalid) : "";
    }

    canAccept: serviceReady && to.recipients.length > 0 && invalid === ""
    onFieldsChanged: {
        if (!ready)
            return;
        edited = true;
        autosave.restart();
    }
    onAcceptBlocked: {
        showErrors = true;
        Notices.show(!serviceReady ? qsTr("Add a mail account before sending") : invalid !== "" ? qsTr("“%1” isn't an email address").arg(invalid) : qsTr("Add a recipient first"));
    }
    onAccepted: {
        autosave.stop();
        if (mail.send(to.recipients.join(", "), cc.recipients.join(", "), bcc.recipients.join(", "), subjectField.text, bodyArea.text, [])) {
            draftStore.value = Logic.withDraft(draftStore.value, draftKey, { to: "", cc: "", bcc: "", subject: "", body: "" }, 0);
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
        if (Logic.parseDrafts(draftStore.value)[draftKey])
            Notices.show(qsTr("Draft saved"));
    }
    Component.onCompleted: {
        const d = Logic.parseDrafts(draftStore.value)[draftKey];
        if (d) {
            toField.text = d.to || "";
            ccField.text = d.cc || "";
            bccField.text = d.bcc || "";
            subjectField.text = d.subject || "";
            bodyArea.text = d.body || "";
            showCopies = ccField.text !== "" || bccField.text !== "";
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
                readonly property string kind: Logic.draftKind(dialog.draftKey)

                acceptText: qsTr("Send")
                title: kind === "forward" ? qsTr("Forward") : kind === "reply" ? qsTr("Reply") : qsTr("New message")
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
                errorHighlight: dialog.to.invalid !== "" && (!activeFocus || dialog.showErrors)
                description: errorHighlight ? dialog.invalidText(dialog.to) : ""
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: (dialog.showCopies ? ccField : subjectField).focus = true
            }
            BackgroundItem {
                objectName: "copiesItem"
                visible: !dialog.showCopies && dialog.serviceReady
                onClicked: {
                    dialog.showCopies = true;
                    ccField.focus = true;
                }

                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Cc/Bcc")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }
            TextField {
                id: ccField

                objectName: "ccField"
                width: parent.width
                visible: dialog.showCopies
                enabled: dialog.serviceReady
                label: qsTr("Cc")
                placeholderText: qsTr("Cc")
                text: dialog.defaultCc
                errorHighlight: dialog.cc.invalid !== "" && (!activeFocus || dialog.showErrors)
                description: errorHighlight ? dialog.invalidText(dialog.cc) : ""
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: bccField.focus = true
            }
            TextField {
                id: bccField

                objectName: "bccField"
                width: parent.width
                visible: dialog.showCopies
                enabled: dialog.serviceReady
                label: qsTr("Bcc")
                placeholderText: qsTr("Bcc")
                errorHighlight: dialog.bcc.invalid !== "" && (!activeFocus || dialog.showErrors)
                description: errorHighlight ? dialog.invalidText(dialog.bcc) : ""
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
                backgroundStyle: TextEditor.NoBackground
                placeholderText: qsTr("Message")
                text: dialog.defaultBody
            }
        }

        VerticalScrollDecorator {}
    }
}
