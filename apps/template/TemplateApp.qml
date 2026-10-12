pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property QtObject store: ConfigurationValue {
        key: "/apps/template/items"
        defaultValue: "[]"
    }
    readonly property var items: {
        try {
            const parsed = JSON.parse(store.value);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    function addItem() {
        store.value = JSON.stringify(items.concat([qsTr("Item %1").arg(items.length + 1)]));
    }

    function removeItem(index) {
        store.value = JSON.stringify(items.filter((_, i) => i !== index));
    }

    appId: "template"

    cover: Component {
        TemplateCover {
            count: app.items.length
            onAddRequested: {
                app.activate();
                app.addItem();
            }
        }
    }

    initialPage: Component {
        MainPage {
            app: app
        }
    }
}
