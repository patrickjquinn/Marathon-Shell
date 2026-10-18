import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "models"
import "pages"
import "cover"

ApplicationWindow {
    id: root

    property StoreBackend store: StoreBackend {}
    property Connections _storeEvents: Connections {
        target: root.store
        function onPushRequested(page, properties) {
            root.pageStack.push(page, properties);
        }
        function onJobFinished(appId, verb, job) {
            Notices.show(root.noticeFor(appId, verb, job));
        }
    }

    function noticeFor(appId, verb, job) {
        const name = store.nameOf(appId);
        if (job.state === "cancelled")
            return (verb === "update" ? qsTr("Cancelled updating %1") : qsTr("Cancelled installing %1")).arg(name);
        if (job.state === "failed")
            return (verb === "uninstall" ? qsTr("Couldn't remove %1.") : verb === "update" ? qsTr("Couldn't update %1.") : qsTr("Couldn't install %1.")).arg(name) + " " + store.jobError(job);
        if (verb === "uninstall")
            return qsTr("%1 removed").arg(name);
        return (verb === "update" ? qsTr("%1 updated") : qsTr("%1 installed")).arg(name);
    }

    appId: "store"
    Component.onCompleted: store.loadCatalog()

    StoreActions {
        app: root
    }

    cover: Component {
        StoreCover {
            store: root.store
            onSearchRequested: {
                root.activate();
                if (root.pageStack.depth > 1)
                    root.pageStack.pop(null, PageStackAction.Immediate);
                root.pageStack.currentPage.showSearch();
            }
        }
    }
    initialPage: Component {
        MainPage {
            store: root.store
        }
    }
}
