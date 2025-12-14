#include "BrowserData.h"

#include <QtWebEngineQuick/QQuickWebEngineProfile>
#include <QtWebEngineCore/QWebEngineCookieStore>

BrowserData::BrowserData(QObject *parent)
    : QObject(parent) {}

BrowserData *BrowserData::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine) {
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)
    return new BrowserData();
}

bool BrowserData::clearCookiesAndCache(QObject *webEngineProfileObject) {
    auto *profile = qobject_cast<QQuickWebEngineProfile *>(webEngineProfileObject);
    if (!profile)
        return false;

    if (auto *store = profile->cookieStore()) {
        store->deleteSessionCookies();
        store->deleteAllCookies();
    }

    // Async; QML can listen to clearHttpCacheCompleted if it cares.
    profile->clearHttpCache();
    return true;
}
