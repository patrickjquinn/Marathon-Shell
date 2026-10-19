import QtQuick
import QtTest
import "../NotesStore.js" as Store

TestCase {
    name: "NotesStore"

    function note(id, extra) {
        return Object.assign({ id: id, title: "N" + id, content: "", timestamp: id }, extra || {});
    }

    function test_sharedTextKeepsALinksTitle() {
        compare(Store.sharedText([{ name: "", data: "Buy milk" }]), "Buy milk");
        compare(Store.sharedText([{ name: "Marathon", data: "https://marathonos.org" }]), "Marathon\nhttps://marathonos.org");
        compare(Store.sharedText([{ name: "x", data: "x" }, { name: "", data: "y" }]), "x\n\ny");
        compare(Store.sharedText([{ name: "photo.png", data: "", filePath: "/tmp/photo.png" }]), "");
    }

    function test_parseBad() {
        compare(Store.parse(""), []);
        compare(Store.parse(undefined), []);
        compare(Store.parse("{oops"), []);
        compare(Store.parse("{\"a\":1}"), []);
    }

    function test_create() {
        const n = Store.create([], "", 1000);
        compare(n.length, 1);
        compare(n[0].id, 1);
        compare(n[0].title, "");
        const m = Store.create(n, "\n  Shopping \nmilk", 2000);
        compare(m[0].id, 2);
        compare(m[0].title, "Shopping");
        compare(m[0].content, "\n  Shopping \nmilk");
    }

    function test_updateKeepsPinAndTag() {
        const n = Store.update([note(1, { pinned: true, tag: "work" })], 1, "x\ny", 5);
        compare(n[0].title, "x");
        compare(n[0].content, "x\ny");
        compare(n[0].timestamp, 5);
        verify(n[0].pinned);
        compare(n[0].tag, "work");
    }

    function test_updateMissingIsNoop() {
        const n = [note(1)];
        compare(Store.update(n, 99, "z", 6), n);
    }

    function test_textJoinsSeparateLegacyTitle() {
        compare(Store.text(note(1, { title: "Shop", content: "milk" })), "Shop\nmilk");
        compare(Store.text(note(1, { title: "Shop", content: "Shop\nmilk" })), "Shop\nmilk");
        compare(Store.text(note(1, { title: "Untitled", content: "milk" })), "milk");
        compare(Store.text(note(1, { title: "", content: "milk" })), "milk");
        compare(Store.text(note(1, { title: "Shop", content: "" })), "Shop");
    }

    function test_previewSkipsTitleLine() {
        compare(Store.preview(note(1, { title: "Shop", content: "Shop\nmilk\n  eggs" })), "milk eggs");
        compare(Store.preview(note(1, { title: "Shop", content: "milk" })), "milk");
        compare(Store.preview(note(1, { title: "", content: "only" })), "");
    }

    function test_whenTodayIsATime() {
        const now = new Date(2026, 9, 12, 18, 0);
        verify(Store.when(new Date(2026, 9, 12, 9, 5).getTime(), now).indexOf("9") >= 0);
        compare(Store.when(new Date(2026, 9, 5, 9, 5).getTime(), now), "5 Oct");
        compare(Store.when(new Date(2025, 8, 7).getTime(), now), "7 Sep 2025");
    }

    function test_remove() {
        compare(Store.remove([note(1), note(2)], 1).map(n => n.id), [2]);
    }

    function test_setPinnedKeepsTimestamp() {
        const n = Store.setPinned([note(1)], 1, true);
        verify(n[0].pinned);
        compare(n[0].timestamp, 1);
        verify(!Store.setPinned(n, 1, false)[0].pinned);
    }

    function test_sortedPinnedFirstThenNewest() {
        const s = Store.sorted([note(1), note(3), note(2, { pinned: true })]);
        compare(s.map(n => n.id), [2, 3, 1]);
    }

    function test_searchTitleAndContent() {
        const all = [note(1, { title: "Groceries" }), note(2, { content: "buy MILK" }), note(3)];
        compare(Store.search(all, "").length, 3);
        compare(Store.search(all, "groc").map(n => n.id), [1]);
        compare(Store.search(all, "milk").map(n => n.id), [2]);
        compare(Store.search(all, "zzz").length, 0);
    }

    function test_tagFromFieldOrHashtag() {
        compare(Store.tagOf(note(1, { tag: "work" })), "work");
        compare(Store.tagOf(note(1, { content: "call bob #home soon #later" })), "home");
        compare(Store.tagOf(note(1, { content: "issue#12 is not a tag" })), "");
        compare(Store.tagOf(note(1)), "");
    }

    function test_foldersUntaggedLast() {
        const f = Store.folders([note(1, { tag: "work" }), note(2), note(3, { content: "#home" }), note(4, { tag: "work" })]);
        compare(f, [{ tag: "home", count: 1 }, { tag: "work", count: 2 }, { tag: "", count: 1 }]);
        compare(Store.inFolder([note(1, { tag: "work" }), note(2)], "work").map(n => n.id), [1]);
        compare(Store.inFolder([note(1, { tag: "work" }), note(2)], "").map(n => n.id), [2]);
    }

    function test_tasks() {
        const t = Store.tasks([note(7, { content: "intro\n- [ ] milk\n- [x] eggs\n[X] bread" })]);
        compare(t.length, 3);
        compare(t[0], { noteId: 7, noteTitle: "N7", line: 1, checked: false, text: "milk" });
        verify(t[1].checked);
        verify(t[2].checked);
        compare(t[2].line, 3);
    }

    function test_toggleTask() {
        const n = Store.toggleTask([note(7, { content: "a\n- [ ] milk" })], 7, 1, 9);
        compare(n[0].content, "a\n- [x] milk");
        compare(n[0].timestamp, 9);
        compare(Store.toggleTask(n, 7, 1, 10)[0].content, "a\n- [ ] milk");
        compare(Store.toggleTask(n, 7, 0, 10), n);
        compare(Store.toggleTask(n, 99, 1, 10), n);
    }

    function test_mergeIntoEmptyKeepsIds() {
        const m = Store.merge([], [note(4, { pinned: true, tag: "x" }), note(9)]);
        compare(m.map(n => n.id), [4, 9]);
        verify(m[0].pinned);
        compare(m[0].tag, "x");
    }

    function test_mergeRenumbersClashes() {
        const m = Store.merge([note(1), note(2)], [note(2), note(5)]);
        compare(m.map(n => n.id), [1, 2, 3, 5]);
    }

    function test_mergeNormalisesLegacyNotes() {
        const m = Store.merge([], [{ id: 1, title: "", content: null, timestamp: 3 }, "junk", { title: "no id" }]);
        compare(m.length, 2);
        compare(m[0].title, "");
        compare(m[0].content, "");
        compare(m[1].id, 2);
        compare(typeof m[1].timestamp, "number");
    }
}
