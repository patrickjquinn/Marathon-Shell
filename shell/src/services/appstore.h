#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QString>
#include <qqml.h>

class Apps;

class AppStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)

  public:
    // Desktop apps (flatpaks, Android apps) are looked up after Marathon's.
    explicit AppStore(Apps *apps, QObject *parent = nullptr);

    QVariantList apps() const {
        return m_apps;
    }

    Q_INVOKABLE QVariantMap getApp(const QString &appId) const;
    Q_INVOKABLE QString     getAppName(const QString &appId) const;
    Q_INVOKABLE QString     getAppIcon(const QString &appId) const;

  signals:
    void appsChanged();

  private:
    void                 refreshApps();

    QPointer<Apps>       m_appModel;
    QVariantList         m_apps;
};
