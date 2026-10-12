import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Services
import ".."

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

    function test_reply() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "ann@x.org", bodyPlain: "a\nb" });
        findChild(msg, "replyItem").clicked();
        const compose = pushed(app, 3);
        compare(findChild(compose, "toField").text, "ann@x.org");
        compare(findChild(compose, "subjectField").text, "Re: Plan");
        compare(findChild(compose, "bodyArea").text, "\n\n> a\n> b");
        verify(!compose.restoreDraft);
    }

    function test_forward() {
        const app = makeApp();
        const msg = openMessage(app, { subject: "Plan", from: "ann@x.org", bodyPlain: "body" });
        findChild(msg, "forwardItem").clicked();
        const compose = pushed(app, 3);
        compare(findChild(compose, "toField").text, "");
        compare(findChild(compose, "subjectField").text, "Fwd: Plan");
        verify(findChild(compose, "bodyArea").text.indexOf("From: ann@x.org") >= 0);
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
        app.draftStore.value = JSON.stringify({ to: "old@b.co", cc: "", subject: "", body: "" });
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Hi" });
        pushed(app, 2);
        findChild(compose, "ccField").text = "c@b.co";
        findChild(compose, "bodyArea").text = "Body";
        compose.accept();
        pushed(app, 1);
        compare(MailService.called("send")[0].args, ["a@b.co", "c@b.co", "Hi", "Body", []]);
        compare(app.draftStore.value, "");
    }

    function test_composeSendFailureKeepsDraft() {
        MailService.fail = true;
        const app = makeApp();
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Hi" });
        pushed(app, 2);
        compose.accept();
        pushed(app, 1);
        compare(JSON.parse(app.draftStore.value).to, "a@b.co");
    }

    function test_composeRejectSavesEdits() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        findChild(compose, "subjectField").text = "Later";
        compose.reject();
        pushed(app, 1);
        compare(JSON.parse(app.draftStore.value).subject, "Later");
    }

    function test_unchangedReplyKeepsDraft() {
        const app = makeApp();
        const saved = JSON.stringify({ to: "x@y.co", cc: "", subject: "Draft", body: "" });
        app.draftStore.value = saved;
        const compose = app.compose({ defaultTo: "a@b.co", defaultSubject: "Re: Hi" });
        pushed(app, 2);
        compose.reject();
        pushed(app, 1);
        compare(app.draftStore.value, saved);
    }

    function test_composeRestoresDraft() {
        const app = makeApp();
        app.draftStore.value = JSON.stringify({ to: "x@y.co", cc: "z@y.co", subject: "Draft", body: "Text" });
        const compose = app.compose();
        pushed(app, 2);
        compare(findChild(compose, "toField").text, "x@y.co");
        compare(findChild(compose, "ccField").text, "z@y.co");
        compare(findChild(compose, "subjectField").text, "Draft");
        compare(findChild(compose, "bodyArea").text, "Text");
    }

    function test_composeAutosaves() {
        const app = makeApp();
        const compose = app.compose();
        pushed(app, 2);
        findChild(compose, "toField").text = "a@b.co";
        tryVerify(() => app.draftStore.value !== "", 4000);
        compare(JSON.parse(app.draftStore.value).to, "a@b.co");
    }

    // Accounts

    function test_oauthFlow() {
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
        setup.submit();
        verify(findChild(setup, "serverSettings").visible);
        verify(findChild(setup, "error").visible);
        compare(MailService.called("addImapAccount").length, 0);
    }

    function test_imapSubmit() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "me@fastmail.com";
        findChild(setup, "passwordField").text = "pw";
        tap(findChild(setup, "signInButton"));
        verify(setup.busy);
        pushed(app, 1);
        compare(MailService.called("addImapAccount")[0].args, ["me@fastmail.com", "me@fastmail.com", "imap.fastmail.com", 993, 1, "smtp.fastmail.com", 465, 1, "me@fastmail.com", "pw"]);
        verify(app.hasAccount);
    }

    function test_imapSubmitFails() {
        MailService.fail = true;
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        setup.applyPreset("yahoo");
        findChild(setup, "emailField").text = "me@example.org";
        findChild(setup, "passwordField").text = "pw";
        findChild(setup, "nameField").text = "Me";
        setup.submit();
        tryVerify(() => !setup.busy);
        verify(findChild(setup, "error").visible);
        compare(MailService.called("addImapAccount")[0].args[0], "Me");
        compare(app.pageStack.depth, 2);
    }

    function test_imapInvalidEmail() {
        const app = makeApp(false);
        const setup = push(app, "MailAccountSetupPage.qml", 2);
        findChild(setup, "emailField").text = "nope";
        findChild(setup, "passwordField").text = "pw";
        verify(!setup.canSubmit);
        verify(!findChild(setup, "signInButton").enabled);
    }
}
