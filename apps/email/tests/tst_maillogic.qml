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
        compare(Logic.headerDescription("Work", 0), "Work");
        compare(Logic.headerDescription("Work", 3), "Work · 3 unread");
        compare(Logic.headerDescription("", 1), "1 unread");
    }

    function test_draftRoundTrip() {
        compare(Logic.draft({ to: " ", cc: "", subject: "", body: "\n" }), "");
        const json = Logic.draft({ to: "a@b.co", cc: "", subject: "Hi", body: "x" });
        compare(Logic.parseDraft(json), { to: "a@b.co", cc: "", subject: "Hi", body: "x" });
        compare(Logic.parseDraft(""), null);
        compare(Logic.parseDraft("{bad"), null);
    }
}
