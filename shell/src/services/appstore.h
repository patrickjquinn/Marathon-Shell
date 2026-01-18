#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>
#include <qqml.h>

class MarathonAppRegistry;

class AppStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)

  public:
    explicit AppStore(MarathonAppRegistry *appRegistry, QObject *parent = nullptr);

    QVariantList apps() const {
        return m_apps;
    }

    Q_INVOKABLE QVariantMap getApp(const QString &appId) const;
    Q_INVOKABLE QString     getAppName(const QString &appId) const;
    Q_INVOKABLE QString     getAppIcon(const QString &appId) const;
    Q_INVOKABLE bool        isInternalApp(const QString &appId) const;
    Q_INVOKABLE bool        isNativeApp(const QString &appId) const;

  signals:
    void appsChanged();

  private:
    void                 refreshApps();

    MarathonAppRegistry *m_appRegistry;
    QVariantList         m_apps;
};
