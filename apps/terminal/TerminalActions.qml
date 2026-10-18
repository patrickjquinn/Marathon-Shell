import QtQuick
import Keel.Actions 1.0

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml TerminalActions.qml --app-id org.marathonos.terminal \
//       --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
// Nothing here types into a shell.
Item {
    id: root

    // The app: newSession() and activate().
    property var app

    KeelAction {
        name: "terminal.open"
        title: qsTr("Open a terminal")
        description: "Bring Marathon Terminal to the front in a new shell session, for the person to type in. It runs no command."
        idempotent: false
        onInvoked: (args, call) => {
            root.app.newSession();
            root.app.activate();
        }
    }
}
