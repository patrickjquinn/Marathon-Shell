import QtQuick
import QtWebEngine

// No scripts, and no remote images until asked, so tracking pixels stay dark.
WebEngineView {
    id: view

    property string html
    property bool loadImages: false

    settings.autoLoadImages: loadImages
    settings.javascriptEnabled: false
    settings.localContentCanAccessRemoteUrls: false
    settings.localContentCanAccessFileUrls: false
    backgroundColor: "transparent"
    onHtmlChanged: loadHtml(html)
    onLoadImagesChanged: loadHtml(html)
    onLoadingChanged: function (info) {
        if (info.status === WebEngineView.LoadFailedStatus)
            console.warn("Mail: body HTML load failed: " + info.errorString);
    }
}
