pragma Singleton
import QtQml

QtObject {
    property var contacts: []
    property var added: []

    function addContact(name, phone, email) {
        added = added.concat([
            {
                name: name,
                phone: phone
            }
        ]);
        contacts = contacts.concat([
            {
                name: name,
                phone: phone
            }
        ]);
    }
}
