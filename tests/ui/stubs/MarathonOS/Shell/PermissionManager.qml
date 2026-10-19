pragma Singleton
import QtQml
QtObject {
    property bool promptActive: false
    property string currentAppId: ""
    property var currentPermissions: []
    property var currentRefused: []
    property var currentOptions: ({})
    property var responses: []
    function getPermissionLabel(p) { return p.charAt(0).toUpperCase() + p.slice(1); }
    function getPermissionDescription(p) { return "Lets the app use " + p; }
    function respond(allowed) { responses = responses.concat([allowed]); }
    function respondWith(allowed, once, precise) { responses = responses.concat([[allowed, once, precise]]); }
}
