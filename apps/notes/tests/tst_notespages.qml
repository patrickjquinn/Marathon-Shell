import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    id: testCase
    name: "NotesPages"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value
        }
    }
    Component {
        id: appComponent
        NotesApp { width: 540; height: 1140 }
    }

    function note(id, extra) {
        return Object.assign({ id: id, title: "Note " + id, content: "", timestamp: id * 1000 }, extra || {});
    }

    function makeApp(notes, route) {
        const store = createTemporaryObject(valueStub, testCase, { value: JSON.stringify(notes || []) });
        const flag = createTemporaryObject(valueStub, testCase, { value: true });
        const app = createTemporaryObject(appComponent, testCase, { store: store, imported: flag, legacySettings: null, route: route || "" });
        tryVerify(() => app.pageStack.currentPage !== null && app.pageStack.busy === false);
        return app;
    }

    function view(app, name) {
        const v = findChild(app.pageStack.currentPage, name);
        verify(v, name);
        return v;
    }

    function delegateAt(v, index) {
        let item = null;
        tryVerify(() => (item = v.itemAtIndex(index)) !== null);
        return item;
    }

    function tapMenuItem(menu, name) {
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, name));
    }

    // A pull-down from the page's top opens its pulley menu.
    function pulleyIn(item) {
        if (!item)
            return null;
        if (item._isPullDownMenu === true && item.visible)
            return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const found = pulleyIn(children[i]);
            if (found)
                return found;
        }
        return null;
    }

    function pullDown(item) {
        const menu = pulleyIn(item);
        verify(menu, "a pull-down menu");
        const x = item.width / 2;
        mousePress(item, x, 300);
        for (let y = 320; y <= 780; y += 40)
            mouseMove(item, x, y, 16);
        verify(menu.active, "pulley open");
        mouseRelease(item, x, 780);
        return menu;
    }

    function test_notesPulleyOpens() {
        const app = makeApp([note(1), note(2)]);
        pullDown(app.pageStack.currentPage);
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function test_listPinnedFirstThenNewest() {
        const app = makeApp([note(1), note(3), note(2, { pinned: true })]);
        compare(app.pageStack.currentPage.shown.map(n => n.id), [2, 3, 1]);
        compare(view(app, "notesView").count, 3);
    }

    function test_emptyPlaceholder() {
        const app = makeApp([]);
        const p = findChild(app.pageStack.currentPage, "placeholder");
        verify(p.enabled);
        compare(p.text, "No notes");
    }

    function test_searchFilters() {
        const app = makeApp([note(1, { title: "Groceries", content: "milk" }), note(2, { title: "Ideas" })]);
        const field = findChild(view(app, "notesView").headerItem, "searchField");
        field.text = "MILK";
        compare(app.pageStack.currentPage.shown.map(n => n.id), [1]);
        field.text = "nothing";
        const p = findChild(app.pageStack.currentPage, "placeholder");
        verify(p.enabled);
        compare(p.text, "No matching notes");
    }

    function test_searchTakesKeys() {
        const app = makeApp([note(1, { title: "Groceries", content: "milk" }), note(2, { title: "Ideas" })]);
        const field = findChild(view(app, "notesView").headerItem, "searchField");
        mouseClick(field);
        keyClick(Qt.Key_M);
        keyClick(Qt.Key_I);
        compare(field.text, "mi");
        compare(app.pageStack.currentPage.shown.map(n => n.id), [1]);
        verify(field.activeFocus);
    }

    function test_tapOpensEditor() {
        const app = makeApp([note(1), note(2)]);
        mouseClick(delegateAt(view(app, "notesView"), 0));
        const editor = pushed(app, 2);
        compare(editor.noteId, 2);
        compare(findChild(editor, "bodyField").text, "Note 2");
    }

    function test_pulleyNewNote() {
        const app = makeApp([]);
        findChild(app.pageStack.currentPage, "newNoteItem").clicked(null);
        compare(pushed(app, 2).noteId, -1);
    }

    function test_contextMenuPins() {
        const app = makeApp([note(1), note(2)]);
        const menu = delegateAt(view(app, "notesView"), 1).openMenu();
        tapMenuItem(menu, "pinItem");
        tryVerify(() => app.notes.find(n => n.id === 1).pinned === true);
        compare(app.pageStack.currentPage.shown[0].id, 1);
    }

    function test_contextMenuRemorseDelete() {
        const app = makeApp([note(1), note(2)]);
        const menu = delegateAt(view(app, "notesView"), 0).openMenu();
        tapMenuItem(menu, "deleteItem");
        compare(app.notes.length, 2);
        tryVerify(() => app.notes.length === 1, 10000);
        compare(app.notes[0].id, 1);
    }

    function test_foldersFromTagsAndHashtags() {
        const app = makeApp([note(1, { tag: "work" }), note(2, { content: "see #home" }), note(3)], "/folders");
        const folders = pushed(app, 2);
        const v = findChild(folders, "foldersView");
        compare(v.count, 3);
        mouseClick(delegateAt(v, 1));
        const inFolder = pushed(app, 3);
        compare(inFolder.folder, "work");
        compare(inFolder.shown.map(n => n.id), [1]);
    }

    function test_tasksToggle() {
        const app = makeApp([note(4, { content: "list\n- [ ] milk" })], "/tasks");
        const tasks = pushed(app, 2);
        const sw = findChild(delegateAt(findChild(tasks, "tasksView"), 0), "taskSwitch");
        verify(!sw.checked);
        mouseClick(sw);
        tryVerify(() => app.notes[0].content === "list\n- [x] milk");
        tryVerify(() => findChild(delegateAt(findChild(tasks, "tasksView"), 0), "taskSwitch").checked);
    }

    function test_taskRowTapToggles() {
        const app = makeApp([note(4, { content: "list\n- [ ] milk" })], "/tasks");
        const tasks = pushed(app, 2);
        mouseClick(delegateAt(findChild(tasks, "tasksView"), 0), 400, 20);
        tryVerify(() => app.notes[0].content === "list\n- [x] milk");
        compare(app.pageStack.depth, 2);
    }

    function test_taskMenuOpensNote() {
        const app = makeApp([note(4, { content: "- [ ] milk" })], "/tasks");
        const tasks = pushed(app, 2);
        const menu = delegateAt(findChild(tasks, "tasksView"), 0).openMenu();
        tapMenuItem(menu, "openNoteItem");
        compare(pushed(app, 3).noteId, 4);
    }

    function test_coverNewNote() {
        const app = makeApp([]);
        app.newNote();
        compare(pushed(app, 2).noteId, -1);
    }
}
