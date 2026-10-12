pragma Singleton
import QtQml

QtObject {
    property var accounts: []
    readonly property int accountCount: accounts.length
    property bool syncing: false
    property string lastError: ""
    property real lastSyncMs: 0
    property var calls: []

    signal accountDiscovered(string accountId)
    signal accountDiscoveryFailed(string accountId, string reason)

    function reset() {
        accounts = [];
        syncing = false;
        lastError = "";
        lastSyncMs = 0;
        calls = [];
    }
    function addAccount(name, url, user, secret, auth) {
        const id = "acc" + (accounts.length + 1);
        accounts = accounts.concat([{ id: id, displayName: name, baseUrl: url, username: user }]);
        calls = calls.concat([["add", name, url, user, secret, auth]]);
        return id;
    }
    function removeAccount(id) {
        accounts = accounts.filter(a => a.id !== id);
        calls = calls.concat([["remove", id]]);
        return true;
    }
    function enableAccount(id, enabled) {
        accounts = accounts.map(a => a.id === id ? Object.assign({}, a, { enabled: enabled }) : a);
        calls = calls.concat([["enable", id, enabled]]);
    }
    function syncNow() {
        calls = calls.concat([["sync"]]);
    }
}
