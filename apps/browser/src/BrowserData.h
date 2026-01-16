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

    Q_INVOKABLE bool    clearCookiesAndCache(QObject *webEngineProfileObject);
};
