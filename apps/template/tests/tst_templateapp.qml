import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."
import "../cover"

TestCase {
    id: testCase
    name: "TemplateApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value
        }
    }
    Component {
        id: appComponent
        TemplateApp {
            width: 540
            height: 1140
        }
    }
    Component {
        id: coverComponent
        TemplateCover {}
    }
    SignalSpy {
        id: addSpy
        signalName: "addRequested"
    }

    function makeApp(items) {
        const store = createTemporaryObject(valueStub, testCase, {
            value: JSON.stringify(items || [])
        });
        const app = createTemporaryObject(appComponent, testCase, {
            store: store
        });
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
        return app;
    }

    function view(app) {
        return findChild(app.pageStack.currentPage, "itemsView");
    }

    function test_storeIsAConfigurationValue() {
        const app = createTemporaryObject(appComponent, testCase);
        compare(app.store.key, "/apps/template/items");
    }

    function test_corruptStoreStartsEmpty() {
        const store = createTemporaryObject(valueStub, testCase, {
            value: "{nope"
        });
        compare(createTemporaryObject(appComponent, testCase, {
            store: store
        }).items.length, 0);
    }

    function test_emptyShowsPlaceholder() {
        const app = makeApp([]);
        verify(findChild(app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_pulleyAddsItem() {
        const app = makeApp([]);
        findChild(app.pageStack.currentPage, "addItem").clicked();
        findChild(app.pageStack.currentPage, "addItem").clicked();
        compare(texts(app), ["Item 1", "Item 2"]);
        verify(app.items[0].id !== app.items[1].id);
        compare(JSON.parse(app.store.value), app.items);
        tryCompare(view(app), "count", 2);
        verify(!findChild(app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_contextMenuRemorseDelete() {
        const app = makeApp([
            {
                id: 1,
                text: "A"
            },
            {
                id: 2,
                text: "B"
            }
        ]);
        openDelete(app, 0);
        compare(app.items.length, 2);
        tryVerify(() => app.items.length === 1, 10000);
        compare(texts(app), ["B"]);
    }

    function test_remorseDeletesTheRightItemWhenTheListChanges() {
        const app = makeApp([
            {
                id: 1,
                text: "A"
            },
            {
                id: 2,
                text: "B"
            },
            {
                id: 3,
                text: "C"
            }
        ]);
        openDelete(app, 1);
        app.removeItem(1);
        tryVerify(() => app.items.length === 1, 10000);
        compare(texts(app), ["C"]);
    }

    function openDelete(app, index) {
        let delegate = null;
        tryVerify(() => (delegate = view(app).itemAtIndex(index)) !== null);
        const menu = delegate.openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, "deleteItem"));
    }

    function texts(app) {
        return app.items.map(i => i.text);
    }

    function test_coverShowsCountAndAdds() {
        const c = createTemporaryObject(coverComponent, testCase, {
            count: 0
        });
        verify(findChild(c, "coverPlaceholder").visible);
        c.count = 2;
        verify(!findChild(c, "coverPlaceholder").visible);
        verify(findChild(c, "coverCount").visible);
        compare(findChild(c, "coverCount").value, "2");
        compare(findChild(c, "coverCount").label, "items");
        addSpy.target = c;
        addSpy.clear();
        findChild(c, "addAction").triggered();
        compare(addSpy.count, 1);
    }
}
