import QtQuick
import QtTest
import "../MailLogic.js" as Logic

TestCase {
    name: "MailLogic"

    function test_emailValid() {
        verify(Logic.emailValid("a@b.co"));
        verify(Logic.emailValid("  a@b.co "));
        verify(!Logic.emailValid("a@b"));
        verify(!Logic.emailValid("a b@c.de"));
        verify(!Logic.emailValid(""));
    }

    function test_matchesMessage() {
        const m = { from: "Ann <ann@x.org>", subject: "Lunch", snippet: "at noon" };
        verify(Logic.matchesMessage(m, ""));
        verify(Logic.matchesMessage(m, " ANN "));
        verify(Logic.matchesMessage(m, "lunch"));
        verify(Logic.matchesMessage(m, "noon"));
        verify(!Logic.matchesMessage(m, "dinner"));
        verify(!Logic.matchesMessage({}, "x"));
    }

    function test_presetForEmail() {
        compare(Logic.presetForEmail("me@FastMail.com"), "fastmail");
        compare(Logic.presetForEmail("me@me.com"), "icloud");
        compare(Logic.presetForEmail("me@ymail.com"), "yahoo");
        compare(Logic.presetForEmail("me@example.org"), "");
        compare(Logic.presetForEmail("me"), "");
    }

    function test_replyPrefill() {
        const p = Logic.replyPrefill({ from: "Ann <ann@x.org>", subject: "Lunch", bodyPlain: "one\ntwo" });
        compare(p.defaultTo, "Ann <ann@x.org>");
        compare(p.defaultSubject, "Re: Lunch");
        compare(p.defaultBody, "\n\n> one\n> two");
        compare(Logic.replyPrefill({ subject: "RE: Lunch" }).defaultSubject, "RE: Lunch");
    }

    function test_forwardPrefill() {
        const p = Logic.forwardPrefill({ from: "ann@x.org", subject: "Plan", to: ["me@x.org"], bodyPlain: "body" }, "1/2/26 10:00");
        compare(p.defaultSubject, "Fwd: Plan");
        verify(p.defaultTo === undefined);
        compare(p.defaultBody, "\n\n---------- Forwarded message ----------\nFrom: ann@x.org\nDate: 1/2/26 10:00\nSubject: Plan\nTo: me@x.org\n\nbody");
        compare(Logic.forwardPrefill({ subject: "fwd: Plan" }, "").defaultSubject, "fwd: Plan");
    }

    function test_oauthErrorText() {
        verify(Logic.oauthErrorText("oauth_not_configured", "").indexOf("Other (IMAP)") >= 0);
        verify(Logic.oauthErrorText("x", "MARATHON_PERM_SECRET_SERVICE not granted").indexOf("keyring") >= 0);
        verify(Logic.oauthErrorText("x", "connect timeout").indexOf("connection") >= 0);
        compare(Logic.oauthErrorText("x", "weird"), "Sign-in didn't complete. Try again.");
    }

    function test_headerDescription() {
        compare(Logic.headerDescription("Work", 0, 0), "Work");
        compare(Logic.headerDescription("Work", 3, 0), "Work · 3 unread");
        compare(Logic.headerDescription("", 1, 0), "1 unread");
        compare(Logic.headerDescription("Work", 0, 2), "Work · 2 in Outbox");
        compare(Logic.headerDescription("Work", 1, 1), "Work · 1 unread · 1 in Outbox");
    }

    function test_parseRecipients() {
        compare(Logic.parseRecipients("a@b.co; c@d.org,e@f.net"), { recipients: ["a@b.co", "c@d.org", "e@f.net"], invalid: "" });
        compare(Logic.parseRecipients(" a@b.co  c@d.org ").recipients, ["a@b.co", "c@d.org"]);
        compare(Logic.parseRecipients("Ann Lee <ann@x.org>, <b@x.org>").recipients, ["Ann Lee <ann@x.org>", "b@x.org"]);
        compare(Logic.parseRecipients('"Lee, Ann" <ann@x.org>').recipients, ['"Lee, Ann" <ann@x.org>']);
        compare(Logic.parseRecipients("a@b.co, bob").invalid, "bob");
        compare(Logic.parseRecipients("Bob <bob>").invalid, "Bob <bob>");
        compare(Logic.parseRecipients(" ; ").recipients, []);
    }

    function test_failureTexts() {
        verify(Logic.sendFailureText("offline").indexOf("offline") >= 0);
        verify(Logic.sendFailureText("server").indexOf("Outbox") >= 0);
        verify(Logic.setupFailureText("offline").indexOf("You're offline") === 0);
        verify(Logic.setupFailureText("login").indexOf("app password") >= 0);
        verify(Logic.setupFailureText("x").indexOf("server settings") >= 0);
    }

    function test_drafts() {
        const empty = { to: " ", cc: "", bcc: "", subject: "", body: "\n" };
        compare(Logic.withDraft("{}", "new-1", empty, 5), "{}");
        let json = Logic.withDraft("", "new-1", { to: "a@b.co", cc: "", bcc: "", subject: "Hi", body: "x" }, 5);
        json = Logic.withDraft(json, "reply-7", { to: "c@d.co", cc: "", bcc: "", subject: "Re: Yo", body: "" }, 9);
        const list = Logic.draftList(Logic.parseDrafts(json));
        compare(list.map(d => d.key), ["reply-7", "new-1"]);
        compare(list[1].subject, "Hi");
        compare(Logic.draftList(Logic.parseDrafts(Logic.withDraft(json, "reply-7", empty, 10))).length, 1);
        compare(Logic.parseDrafts("{bad"), {});
        compare(Logic.parseDrafts("[]"), {});
        compare(Logic.draftKind("reply-7"), "reply");
        compare(Logic.draftKind("new-12"), "new");
    }

    function test_folderIcon() {
        compare(Logic.folderIcon("trash"), "image://theme/icon-m-delete");
        compare(Logic.folderIcon("whatever"), "image://theme/icon-m-folder");
    }
}
