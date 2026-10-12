import QtQuick
import QtWebEngine

// Offline rendering: no scripts or remote loads, so tracking pixels stay dark.
WebEngineView {
    id: view

    property string html

    settings.autoLoadImages: false
    settings.javascriptEnabled: false
    settings.localContentCanAccessRemoteUrls: false
    settings.localContentCanAccessFileUrls: false
    backgroundColor: "transparent"
    onHtmlChanged: loadHtml(html)
    onLoadingChanged: function (info) {
        if (info.status === WebEngineView.LoadFailedStatus)
            console.warn("Mail: body HTML load failed: " + info.errorString);
    }
}
