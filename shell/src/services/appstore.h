#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QString>
#include <qqml.h>

class AppModel;
class MarathonAppRegistry;

class AppStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)

  public:
    explicit AppStore(MarathonAppRegistry *appRegistry, QObject *parent = nullptr);
    // Desktop apps (flatpaks, Android apps) are looked up there after the registry.
    void setAppModel(AppModel *apps);

    QVariantList apps() const {
        return m_apps;
    }

    Q_INVOKABLE QVariantMap getApp(const QString &appId) const;
    Q_INVOKABLE QString     getAppName(const QString &appId) const;
    Q_INVOKABLE QString     getAppIcon(const QString &appId) const;
    Q_INVOKABLE bool        isNativeApp(const QString &appId) const;

  signals:
    void appsChanged();

  private:
    void                 refreshApps();

    MarathonAppRegistry *m_appRegistry;
    QPointer<AppModel>   m_appModel;
    QVariantList         m_apps;
};
