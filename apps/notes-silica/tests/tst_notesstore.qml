import QtQuick
import QtTest
import "../NotesStore.js" as Store

TestCase {
    name: "NotesStore"

    function test_parseBad() {
        compare(Store.parse(""), []);
        compare(Store.parse("{oops"), []);
        compare(Store.parse("{\"a\":1}"), []);
    }
    function test_create() {
        const n = Store.create([], "", "body", 1000);
        compare(n.length, 1);
        compare(n[0].id, 1);
        compare(n[0].title, "Untitled");
        const m = Store.create(n, "B", "", 2000);
        compare(m[0].id, 2);
        compare(m[0].title, "B");
    }
    function test_updateAndRemove() {
        let n = Store.create([], "A", "", 1);
        n = Store.update(n, 1, "A2", "x", 5);
        compare(n[0].title, "A2");
        compare(n[0].timestamp, 5);
        compare(Store.update(n, 99, "z", "z", 6), n);
        compare(Store.remove(n, 1).length, 0);
    }
}
