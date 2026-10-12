pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import MarathonApp.Terminal
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property var sessions: []
    property int currentIndex: 0
    readonly property var currentSession: sessions[currentIndex] || null

    readonly property int minFontSize: Math.round(Theme.fontSizeTiny * 0.75)
    readonly property int maxFontSize: Theme.fontSizeExtraLarge
    property QtObject fontSize: ConfigurationValue {
        key: "/apps/terminal/fontSize"
        defaultValue: Theme.fontSizeTiny
    }
    // "ambience", "dark" or "light"
    property QtObject colorScheme: ConfigurationValue {
        key: "/apps/terminal/colorScheme"
        defaultValue: "ambience"
    }
    property QtObject extraKeys: ConfigurationValue {
        key: "/apps/terminal/extraKeys"
        defaultValue: true
    }

    function newSession() {
        const session = engineComponent.createObject(app);
        sessions = sessions.concat([session]);
        currentIndex = sessions.length - 1;
        session.start();
    }

    function closeSession(index) {
        if (sessions.length < 2 || index < 0 || index >= sessions.length)
            return;
        const session = sessions[index];
        const next = sessions.slice();
        next.splice(index, 1);
        if (currentIndex >= index && currentIndex > 0)
            currentIndex--;
        sessions = next;
        session.destroy();
    }

    function _finished(session) {
        const index = sessions.indexOf(session);
        if (index < 0 || session.failed)
            return;
        if (sessions.length > 1)
            closeSession(index);
        else
            session.start();
    }

    appId: "terminal"
    Component.onCompleted: newSession()

    Component {
        id: engineComponent

        TerminalEngine {
            id: engine

            onFinished: app._finished(engine)
        }
    }

    cover: Component {
        TerminalCover {
            session: app.currentSession
            onNewSessionRequested: {
                app.activate();
                app.newSession();
            }
        }
    }

    initialPage: Component {
        TerminalPage {
            app: app
        }
    }
}
