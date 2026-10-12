pragma Singleton
import QtQml

QtObject {
    property var contacts: []
    property int nextId: 100

    function reset() {
        contacts = [];
        nextId = 100;
    }
    function addContact(name, phone, email) {
        contacts = contacts.concat([{ id: nextId++, name: name, phone: phone, email: email, favorite: false }]);
    }
    function updateContact(id, data) {
        contacts = contacts.map(c => c.id === id ? Object.assign({}, c, data) : c);
    }
    function deleteContact(id) {
        contacts = contacts.filter(c => c.id !== id);
    }
}
