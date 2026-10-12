import QtQuick
import ".."

// The app with in-memory stores and the stub web layer.
BrowserApp {
    width: 540
    height: 1140
    bookmarkStore: QtObject {
        property var value: "[]"
    }
    historyStore: QtObject {
        property var value: "[]"
    }
    tabStore: QtObject {
        property var value: "[]"
    }
    engineStore: QtObject {
        property var value: "DuckDuckGo"
    }
    engineUrlStore: QtObject {
        property var value: "https://duckduckgo.com/?q="
    }
    homepageStore: QtObject {
        property var value: "https://duckduckgo.com"
    }
    maxTabsStore: QtObject {
        property var value: 12
    }
    imported: QtObject {
        property var value: true
    }
    webLayerSource: Qt.resolvedUrl("WebLayerStub.qml")
}
