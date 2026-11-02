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
        contacts = contacts.concat([
            {
                id: nextId++,
                name: name,
                phone: phone,
                email: email,
                favorite: false
            }
        ]);
    }
    // As marathon-davd fills `phone` and `email` from the lists.
    function createContact(data) {
        addContact(data.name, data.phones.length > 0 ? data.phones[0].value : "", data.emails.length > 0 ? data.emails[0].value : "");
        updateContact(nextId - 1, data);
    }
    function updateContact(id, data) {
        if (data.phones)
            data = Object.assign({
                phone: data.phones.length > 0 ? data.phones[0].value : ""
            }, data);
        if (data.emails)
            data = Object.assign({
                email: data.emails.length > 0 ? data.emails[0].value : ""
            }, data);
        contacts = contacts.map(c => c.id === id ? Object.assign({}, c, data) : c);
    }
    function deleteContact(id) {
        contacts = contacts.filter(c => c.id !== id);
    }
}
