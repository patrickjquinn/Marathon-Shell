#pragma once

#include <QObject>
#include <QtQml/QQmlEngine>
#include <QtQml/QJSEngine>
#include <QtQml/qqmlregistration.h>

class BrowserData : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit BrowserData(QObject *parent = nullptr);

    static BrowserData *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    // Clears cookies + HTTP cache for the given QML WebEngineProfile (QtWebEngine Quick).
    // Returns false if the passed object is not a WebEngineProfile.
    Q_INVOKABLE bool clearCookiesAndCache(QObject *webEngineProfileObject);
};
