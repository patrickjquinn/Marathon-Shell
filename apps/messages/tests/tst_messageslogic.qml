import QtQuick
import QtTest
import "../MessagesLogic.js" as Logic

TestCase {
    name: "MessagesLogic"

    readonly property var convs: [
        { id: "a", contactName: "Alice", contactNumber: "+15551234567", lastMessage: "Lunch?", lastTimestamp: 30, unreadCount: 2 },
        { id: "b", contactName: "", contactNumber: "+447700900123", lastMessage: "Code 1234", lastTimestamp: 20, unreadCount: 0 },
        { id: "c", contactName: "Carol", contactNumber: "555", lastMessage: "ok", lastTimestamp: 10, unreadCount: 1 }
    ]

    function test_formatNumber() {
        compare(Logic.formatNumber("+15551234567"), "+1 555 123 4567");
        compare(Logic.formatNumber("+447700900123"), "+44 770 090 0123");
        compare(Logic.formatNumber("*100#"), "*100#");
    }

    function test_sameNumber() {
        verify(Logic.sameNumber("+1 555 123 4567", "5551234567"));
        verify(!Logic.sameNumber("555", "5551"));
        verify(!Logic.sameNumber("", ""));
    }

    function test_displayName() {
        compare(Logic.displayName(convs[0]), "Alice");
        compare(Logic.displayName(convs[1]), "+44 770 090 0123");
    }

    function test_inboxHidesArchivedAndPinsFirst() {
        const list = Logic.visibleConversations(convs, ["c"], ["b"], false, "");
        compare(list.map(c => c.id), ["c", "a"]);
        const many = ["p", "q", "r", "s", "t"].map((id, i) => ({ id: id, lastTimestamp: 10 - i }));
        compare(Logic.visibleConversations(many, ["s"], [], false, "").map(c => c.id), ["s", "p", "q", "r", "t"]);
    }

    function test_archiveShowsOnlyArchived() {
        compare(Logic.visibleConversations(convs, [], ["b"], true, "").map(c => c.id), ["b"]);
    }

    function test_searchMatchesNameNumberAndText() {
        compare(Logic.visibleConversations(convs, [], [], false, "ali").map(c => c.id), ["a"]);
        compare(Logic.visibleConversations(convs, [], [], false, "7700").map(c => c.id), ["b"]);
        compare(Logic.visibleConversations(convs, [], [], false, "lunch").map(c => c.id), ["a"]);
    }

    function test_parseState() {
        compare(Logic.parseState("{oops"), { pinned: [], archived: [], drafts: {} });
        compare(Logic.parseState("[1]").pinned, []);
        const s = Logic.parseState(JSON.stringify({ pinned: ["a"], archived: ["b"], drafts: { a: "hey" } }));
        compare(s.pinned, ["a"]);
        compare(s.archived, ["b"]);
        compare(s.drafts.a, "hey");
    }

    function test_unreadTotal() {
        compare(Logic.unreadTotal(convs), 3);
        compare(Logic.unreadTotal([]), 0);
    }

    function test_recipient() {
        verify(Logic.isPhoneNumber("+44 (0) 7700-900"));
        verify(!Logic.isPhoneNumber("12"));
        verify(!Logic.isPhoneNumber("bob"));
        compare(Logic.normaliseNumber("+44 (0) 7700"), "+4407700");
    }

    function test_messageRowsMarkDaysAndRuns() {
        const day = 24 * 3600 * 1000;
        const base = new Date(2026, 9, 10, 12, 0).getTime();
        const rows = Logic.messageRows([
            { id: 1, text: "hi", timestamp: base, isOutgoing: false },
            { id: 2, text: "there", timestamp: base + 60000, isOutgoing: false },
            { id: 3, text: "yo", timestamp: base + 120000, isOutgoing: true },
            { id: 4, text: "next day", timestamp: base + day, isOutgoing: true }
        ]);
        compare(rows.map(r => r.showDay), [true, false, false, true]);
        compare(rows.map(r => r.showTime), [false, true, true, true]);
    }
}
