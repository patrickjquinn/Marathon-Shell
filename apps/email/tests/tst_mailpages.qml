import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Services
import ".."
import "../MailLogic.js" as Logic

TestCase {
    id: testCase
    name: "MailPages"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value: ""
        }
    }
    Component {
        id: appComponent
        EmailApp { width: 540; height: 1140 }
    }

    function init() {
        MailService.reset();
    }

    function makeApp(account) {
        if (account !== false)
            MailService.setAccount("Work");
        const store = createTemporaryObject(valueStub, testCase);
        const app = createTemporaryObject(appComponent, testCase, { draftStore: store });
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
        return app;
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function push(app, file, depth) {
        app.pageStack.push(Qt.resolvedUrl("../pages/" + file), { app: app });
        return pushed(app, depth);
    }

    function tap(item) {
        tryVerify(() => item.mapToItem(null, 0, 0).y > 0);
        mouseClick(item);
    }

    function openMessage(app, body) {
        MailService.addMessage(7, "Ann", body.subject || "", true);
        MailService.bodies = { "7": body };
        app.openMessage("7");
        return pushed(app, 2);
    }

    // Message page

    function test_messageHeaderAndPlainBody() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "Ann <ann@x.org>", to: ["me@x.org", "b@x.org"], cc: ["c@x.org"], date: new Date(2026, 0, 2, 10, 0), bodyPlain: "Hello" });
        compare(findChild(msg, "fromLabel").text, "Ann <ann@x.org>");
        compare(findChild(msg, "toLabel").text, "To: me@x.org, b@x.org");
        compare(findChild(msg, "ccLabel").text, "Cc: c@x.org");
        compare(findChild(msg, "plainBody").text, "Hello");
        verify(!findChild(msg, "htmlBody").active);
        verify(!findChild(msg, "attachments").visible);
    }

    function test_messageWithoutBody() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Empty", from: "Ann" });
        compare(findChild(msg, "plainBody").text, "This message has no text.");
        verify(!findChild(msg, "ccLabel").visible);
    }

    function test_messageAttachments() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Files", from: "Ann", bodyPlain: "x", attachments: [{ name: "a.pdf", size: 2048 }, { name: "b.png", size: 3145728 }] });
        verify(findChild(msg, "attachments").visible);
        compare(msg.size(2048), "2 kB");
        compare(msg.size(3145728), "3.0 MB");
    }

    function test_messageHtmlUsesWebView() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "News", from: "Ann", bodyHtml: "<p>Hi</p>", bodyPlain: "Hi" });
        verify(findChild(msg, "htmlBody").active);
        verify(!findChild(msg, "plainBody").visible);
    }

    function test_showImagesForThisMessage() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "News", from: "Ann", bodyHtml: "<p>Hi</p>", bodyPlain: "Hi" });
        const body = findChild(msg, "htmlBody");
        tryVerify(() => body.item !== null);
        verify(!body.item.loadImages);
        verify(msg.canShowImages);
        findChild(msg, "showImagesItem").clicked();
        verify(body.item.loadImages);
        verify(!msg.canShowImages);
    }

    function test_plainMessageHasNoShowImages() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "Ann", bodyPlain: "Hello" });
        verify(!msg.canShowImages);
    }

    function test_reply() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "ann@x.org", bodyPlain: "a\nb" });
        findChild(msg, "replyItem").clicked();
        const compose = pushed(app, 3);
        compare(findChild(compose, "toField").text, "ann@x.org");
        compare(findChild(compose, "subjectField").text, "Re: Plan");
        compare(findChild(compose, "bodyArea").text, "\n\n> a\n> b");
        compare(compose.draftKey, "reply-7");
    }

    function test_forward() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "ann@x.org", bodyPlain: "body" });
        findChild(msg, "forwardItem").clicked();
        const compose = pushed(app, 3);
        compare(findChild(compose, "toField").text, "");
        compare(findChild(compose, "subjectField").text, "Fwd: Plan");
        verify(findChild(compose, "bodyArea").text.indexOf("From: ann@x.org") >= 0);
        compare(compose.draftKey, "forward-7");
    }

    function test_replyDraftDoesNotOverwriteNewDraft() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "ann@x.org", bodyPlain: "a" });
        app.draftStore.value = JSON.stringify({ "new-1": { to: "x@y.co", subject: "Mine", savedAt: 1 } });
        findChild(msg, "replyItem").clicked();
        const compose = pushed(app, 3);
        findChild(compose, "bodyArea").text = "Sure";
        compose.reject();
        pushed(app, 2);
        const drafts = Logic.parseDrafts(app.draftStore.value);
        compare(drafts["new-1"].subject, "Mine");
        compare(drafts["reply-7"].body, "Sure");
        findChild(msg, "replyItem").clicked();
        compare(findChild(pushed(app, 3), "bodyArea").text, "Sure");
    }

    function test_attachmentSaveAndFailure() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Files", from: "Ann", bodyPlain: "x", attachments: [{ name: "a.pdf", size: 2048, location: "7-1" }] });
        const row = findChild(msg, "attachment-a.pdf");
        verify(row.enabled);
        msg.saveAttachment("7-1", false);
        compare(MailService.called("saveAttachment")[0].args, ["7", "7-1"]);
        verify(row.busy);
        MailService.attachmentSaved("7", "7-1", "/home/u/Downloads/a.pdf");
        verify(!row.busy);
        compare(msg.savedPaths["7-1"], "/home/u/Downloads/a.pdf");
        msg.savedPaths = {};
        msg.saveAttachment("7-1", true);
        MailService.attachmentFailed("7", "7-1");
        compare(msg.fetching, "");
        compare(msg.savedPaths["7-1"], undefined);
    }

    // Compose

    function test_composeCanAcceptNeedsRecipient() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        verify(!compose.canAccept);
        findChild(compose, "toField").text = "a@b.co";
        verify(compose.canAccept);
    }

    function test_composeRejectsInvalidRecipient() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        const to = findChild(compose, "toField");
        to.text = "a@b.co; bob";
        verify(!compose.canAccept);
        compose.acceptBlocked();
        verify(to.errorHighlight);
        compare(to.description, "“bob” isn't an email address");
        compare(to.text, "a@b.co; bob");
        to.text = "a@b.co; Bob <bob@x.org>";
        verify(compose.canAccept);
        verify(!to.errorHighlight);
    }

    function test_composeBccAndNormalisedRecipients() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        verify(!findChild(compose, "bccField").visible);
        findChild(compose, "copiesItem").clicked(null);
        verify(findChild(compose, "bccField").visible);
        findChild(compose, "toField").text = "a@b.co;c@d.co";
        findChild(compose, "bccField").text = "e@f.co";
        compose.accept();
        pushed(app, 1);
        const args = MailService.called("send")[0].args;
        compare(args[0], "a@b.co, c@d.co");
        compare(args[2], "e@f.co");
    }

    function test_composeWithoutAccount() {
        const app = makeApp(false);
        const compose = app.compose();
        pushed(app, 2);
        verify(findChild(compose, "serviceNotice").visible);
        verify(!findChild(compose, "toField").enabled);
        findChild(compose, "toField").text = "a@b.co";
        verify(!compose.canAccept);
    }

    function test_composeSend() {
        const app = makeApp();
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Hi", draftKey: "new-1" });
        pushed(app, 2);
        findChild(compose, "ccField").text = "c@b.co";
        findChild(compose, "bodyArea").text = "Body";
        compose.persistDraft();
        compose.accept();
        pushed(app, 1);
        compare(MailService.called("send")[0].args, ["a@b.co", "c@b.co", "", "Hi", "Body", []]);
        compare(Logic.parseDrafts(app.draftStore.value)["new-1"], undefined);
    }

    function test_aShareComposesWithItsFiles() {
        const app = makeApp();
        app.receiveShare([{ name: "beach.png", data: "", filePath: "/c/sailfish-share_1/beach.png" }, { name: "", data: "Look", filePath: "" }]);
        const compose = pushed(app, 2);
        compare(findChild(compose, "bodyArea").text, "Look");
        verify(findChild(compose, "composeAttachment-beach.png").visible);
        findChild(compose, "toField").text = "a@b.co";
        compose.accept();
        pushed(app, 1);
        compare(MailService.called("send")[0].args[5], ["/c/sailfish-share_1/beach.png"]);
    }

    function test_aSharedFileCanBeTakenOff() {
        const app = makeApp();
        app.receiveShare([{ name: "a.png", data: "", filePath: "/c/a.png" }, { name: "b.png", data: "", filePath: "/c/b.png" }]);
        const compose = pushed(app, 2);
        tap(findChild(findChild(compose, "composeAttachment-a.png"), "removeAttachment"));
        compare(compose.attachments, ["/c/b.png"]);
    }

    function test_composeSendFailureKeepsDraft() {
        MailService.fail = true;
        const app = makeApp();
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Hi", draftKey: "new-1" });
        pushed(app, 2);
        compose.accept();
        pushed(app, 1);
        compare(Logic.parseDrafts(app.draftStore.value)["new-1"].to, "a@b.co");
    }

    function test_composeRejectSavesEdits() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        findChild(compose, "subjectField").text = "Later";
        compose.reject();
        pushed(app, 1);
        compare(app.drafts.length, 1);
        compare(app.drafts[0].subject, "Later");
    }

    function test_unchangedReplyKeepsDraft() {
        const app = makeApp();
        const saved = JSON.stringify({ "new-1": { to: "x@y.co", subject: "Draft", savedAt: 1 } });
        app.draftStore.value = saved;
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Re: Hi", draftKey: "reply-3" });
        pushed(app, 2);
        compose.reject();
        pushed(app, 1);
        compare(app.draftStore.value, saved);
    }

    function test_newMessageStartsBlank() {
        const app = makeApp();
        app.draftStore.value = JSON.stringify({ "new-1": { to: "x@y.co", subject: "Draft", savedAt: 1 } });
        const compose = app.compose();
        pushed(app, 2);
        compare(findChild(compose, "toField").text, "");
    }

    function test_composeRestoresDraft() {
        const app = makeApp();
        app.draftStore.value = JSON.stringify({ "new-1": { to: "x@y.co", cc: "z@y.co", bcc: "q@y.co", subject: "Draft", body: "Text", savedAt: 1 } });
        const compose = app.compose({ draftKey: "new-1" });
        pushed(app, 2);
        compare(findChild(compose, "toField").text, "x@y.co");
        compare(findChild(compose, "ccField").text, "z@y.co");
        compare(findChild(compose, "bccField").text, "q@y.co");
        verify(findChild(compose, "bccField").visible);
        compare(findChild(compose, "subjectField").text, "Draft");
        compare(findChild(compose, "bodyArea").text, "Text");
    }

    function test_composeAutosaves() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        findChild(compose, "toField").text = "a@b.co";
        tryVerify(() => app.drafts.length === 1, 4000);
        compare(app.drafts[0].to, "a@b.co");
    }

    // Accounts

    function test_oauthProvidersHiddenUntilConfigured() {
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        compare(MailService.called("checkOAuthProviders").length, 1);
        verify(!findChild(add, "provider-gmail"));
        verify(findChild(add, "provider-imap"));
        MailService.oauthProviders = ["gmail"];
        tryVerify(() => findChild(add, "provider-gmail"));
        verify(!findChild(add, "provider-outlook"));
    }

    function test_oauthNeedsNetwork() {
        MailService.oauthProviders = ["gmail", "outlook"];
        MailService.online = false;
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        const gmail = findChild(add, "provider-gmail");
        verify(!gmail.enabled);
        verify(findChild(gmail, "offlineNote").visible);
        verify(findChild(add, "provider-imap").enabled);
        MailService.online = true;
        verify(gmail.enabled);
    }

    function test_oauthCancel() {
        MailService.oauthProviders = ["gmail"];
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        add.signIn("gmail");
        verify(add.waiting);
        findChild(add, "cancelItem").clicked();
        compare(MailService.called("cancelOAuthLogin").length, 1);
        MailService.oauthLoginFailed("cancelled", "Sign-in cancelled");
        verify(!add.waiting);
        verify(!add.failed);
        compare(findChild(add, "status").text, "");
    }

    function test_oauthFlow() {
        MailService.oauthProviders = ["gmail", "outlook"];
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        tap(findChild(add, "provider-gmail"));
        compare(MailService.called("startOAuthLogin")[0].args, ["gmail"]);
        MailService.oauthLoginFailed("oauth_not_configured", "no client id");
        verify(add.failed);
        verify(findChild(add, "status").text.indexOf("Other (IMAP)") >= 0);
        MailService.oauthLoginSucceeded("1");
        pushed(app, 1);
    }

    function test_oauthStartFails() {
        MailService.fail = true;
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        add.signIn("outlook");
        verify(add.failed);
        compare(findChild(add, "status").text, "Sign-in couldn't start. Try again, or use Other (IMAP).");
    }

    function test_imapPageFromProviders() {
        const app = makeApp(false);
        const add = push(app, "AddAccountPage.qml", 2);
        tap(findChild(add, "provider-imap"));
        verify(findChild(pushed(app, 3), "emailField"));
    }

    function test_imapPresetFromDomain() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@icloud.com";
        compare(setup.provider, "icloud");
        compare(findChild(setup, "providerBox").currentIndex, 1);
        compare(findChild(setup, "dialogHeader").title, "iCloud");
        compare(findChild(setup, "imapHostField").text, "imap.mail.me.com");
        compare(findChild(setup, "smtpPortField").text, "587");
        compare(setup.smtpEnc, 2);
        verify(!findChild(setup, "serverSettings").visible);
    }

    function test_imapNeedsServersForUnknownDomain() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@example.org";
        findChild(setup, "passwordField").text = "pw";
        verify(setup.canSubmit);
        verify(!setup.canAccept);
        setup.acceptBlocked();
        verify(findChild(setup, "serverSettings").visible);
        verify(findChild(setup, "error").visible);
        compare(MailService.called("addImapAccount").length, 0);
    }

    function test_imapSubmit() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        verify(setup.canAccept);
        setup.accept();
        verify(setup.busy);
        compare(pushed(app, 3).objectName, "signingInPage");
        compare(MailService.called("addImapAccount")[0].args, ["me@fastmail.com", "me@fastmail.com", "imap.fastmail.com", 993, 1, "smtp.fastmail.com", 465, 1, "me@fastmail.com", "pw"]);
        MailService.setAccount("me@fastmail.com");
        MailService.accountSetupSucceeded("1");
        pushed(app, 1);
        verify(app.hasAccount);
    }

    function test_imapOfflineFailureKeepsPassword() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        setup.submit();
        verify(setup.busy);
        MailService.accountSetupFailed("offline");
        verify(!setup.busy);
        compare(findChild(setup, "error").text, "You're offline. Connect to the internet, then sign in.");
        compare(findChild(setup, "passwordField").text, "pw");
    }

    function test_imapFailureReturnsToForm() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        setup.accept();
        pushed(app, 3);
        MailService.accountSetupFailed("login");
        compare(pushed(app, 2), setup);
        verify(findChild(setup, "error").visible);
        compare(findChild(setup, "passwordField").text, "pw");
    }

    function test_imapCancel() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        setup.accept();
        const waiting = pushed(app, 3);
        findChild(waiting, "cancelItem").clicked();
        compare(MailService.called("cancelAccountSetup").length, 1);
        MailService.accountSetupFailed("cancelled");
        verify(!setup.busy);
        compare(pushed(app, 2), setup);
        verify(!findChild(setup, "error").visible);
    }

    function test_imapBackFromWaitingCancels() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        setup.accept();
        pushed(app, 3);
        app.pageStack.pop();
        pushed(app, 2);
        compare(MailService.called("cancelAccountSetup").length, 1);
    }

    function test_imapSubmitFails() {
        MailService.fail = true;
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        setup.applyPreset("yahoo");
        findChild(setup, "emailField").text = "me@example.org";
        findChild(setup, "passwordField").text = "pw";
        findChild(setup, "nameField").text = "Me";
        setup.accept();
        verify(!setup.busy);
        tryVerify(() => app.pageStack.currentPage === setup && !app.pageStack.busy && findChild(setup, "error").visible, 5000);
        compare(app.pageStack.depth, 2);
        compare(MailService.called("addImapAccount")[0].args[0], "Me");
    }

    function test_imapInvalidEmail() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "nope";
        findChild(setup, "passwordField").text = "pw";
        verify(!setup.canSubmit);
        verify(!setup.canAccept);
    }
}
