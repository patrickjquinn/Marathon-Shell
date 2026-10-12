import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "People"
    when: windowShown
    visible: true
    width: 720
    height: 1440

    QtObject {
        id: seenStub

        property var value: 0
    }
    Component {
        id: appComponent

        PhoneApp {
            width: 720
            height: 1440
        }
    }

    function init() {
        Telephony.reset();
        Contacts.reset();
        CallHistory.reset();
        Permissions.reset();
        Navigation.reset();
        Contacts.contacts = [
            { id: 1, name: "Ada Lovelace", phone: "+44 20 7946 0001", email: "ada@example.com", favorite: false },
            { id: 2, name: "Alan Turing", phone: "555 0101", email: "", favorite: true },
            { id: 3, name: "Grace Hopper", phone: "+1 555 123 4567", email: "", favorite: false }
        ];
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, testCase, { callLogSeen: seenStub });
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function openPeople(app) {
        app.pageStack.currentPage.tabs.moveTo(2);
        let list = null;
        tryVerify(() => (list = findChild(app.pageStack.currentPage, "people")) !== null && list.count === 3);
        return list;
    }

    function waitIdle(app) {
        tryVerify(() => !app.pageStack.busy);
    }

    function test_favoritesFirst() {
        const app = makeApp();
        const list = openPeople(app);
        compare(list.model[0].name, "Alan Turing");
    }

    function test_searchByNameAndNumber() {
        const app = makeApp();
        const list = openPeople(app);
        const search = findChild(list, "searchField");
        search.text = "grace";
        tryCompare(list, "count", 1);
        compare(list.model[0].name, "Grace Hopper");
        search.text = "0101";
        tryCompare(list, "count", 1);
        compare(list.model[0].name, "Alan Turing");
        search.text = "nobody";
        tryCompare(list, "count", 0);
        verify(findChild(list, "peoplePlaceholder").enabled);
    }

    function test_withoutPermissionAsksOnOpen() {
        Permissions.granted = false;
        const app = makeApp();
        compare(Permissions.requests, []);
        app.pageStack.currentPage.tabs.moveTo(2);
        tryCompare(Permissions, "requests", ["contacts"]);
        compare(app.contacts.length, 0);
        Permissions.permissionGranted("phone", "contacts");
        verify(app.hasContactsPermission);
        compare(app.contacts.length, 3);
    }

    function test_contactPageShowsDetailsAndCalls() {
        const app = makeApp();
        const list = openPeople(app);
        list.currentIndex = 1;
        list.currentItem.clicked(null);
        tryVerify(() => app.pageStack.depth === 2);
        waitIdle(app);
        const page = app.pageStack.currentPage;
        compare(findChild(page, "phoneValue").text, "+44 207 946 0001");
        compare(findChild(page, "emailValue").text, "ada@example.com");
        findChild(page, "messageButton").clicked(null);
        compare(Navigation.launches.length, 1);
        compare(JSON.parse(Navigation.launches[0].params).number, "+44 20 7946 0001");
        findChild(page, "phoneItem").clicked(null);
        compare(Telephony.log, ["dial:+44 20 7946 0001"]);
        compare(app.callName, "Ada Lovelace");
    }

    function test_contactPageFavoriteAndDelete() {
        const app = makeApp();
        app.pageStack.push(Qt.resolvedUrl("../pages/ContactPage.qml"), { phone: app, contactId: 3 });
        waitIdle(app);
        const page = app.pageStack.currentPage;
        const star = findChild(page, "favoriteButton");
        compare(star.icon.source.toString(), "image://theme/icon-m-favorite");
        star.clicked(null);
        verify(Contacts.contacts.find(c => c.id === 3).favorite);
        compare(star.icon.source.toString(), "image://theme/icon-m-favorite-selected");
        page.remove();
        compare(Contacts.contacts.length, 3);
        tryVerify(() => Contacts.contacts.length === 2, 8000);
        tryVerify(() => app.pageStack.depth === 1);
    }

    function test_newContactDialogAdds() {
        const app = makeApp();
        app.pageStack.push(Qt.resolvedUrl("../pages/ContactEditorDialog.qml"), { contact: null });
        waitIdle(app);
        const dialog = app.pageStack.currentPage;
        verify(!dialog.canAccept);
        findChild(dialog, "nameField").text = "  Edsger ";
        verify(!dialog.canAccept);
        findChild(dialog, "phoneField").text = "+31 20 555 0000";
        verify(dialog.canAccept);
        dialog.accept();
        tryVerify(() => Contacts.contacts.length === 4);
        compare(Contacts.contacts[3].name, "Edsger");
        compare(Contacts.contacts[3].phone, "+31 20 555 0000");
    }

    function test_editContactDialogUpdates() {
        const app = makeApp();
        app.pageStack.push(Qt.resolvedUrl("../pages/ContactEditorDialog.qml"), { contact: Contacts.contacts[0] });
        waitIdle(app);
        const dialog = app.pageStack.currentPage;
        compare(findChild(dialog, "nameField").text, "Ada Lovelace");
        findChild(dialog, "emailField").text = "ada@analytical.engine";
        dialog.accept();
        tryVerify(() => Contacts.contacts[0].email === "ada@analytical.engine");
        compare(Contacts.contacts.length, 3);
    }

    function test_rejectedDialogDiscards() {
        const app = makeApp();
        app.pageStack.push(Qt.resolvedUrl("../pages/ContactEditorDialog.qml"), { contact: Contacts.contacts[0] });
        waitIdle(app);
        const dialog = app.pageStack.currentPage;
        findChild(dialog, "nameField").text = "Changed";
        dialog.reject();
        waitIdle(app);
        compare(Contacts.contacts[0].name, "Ada Lovelace");
    }
}
