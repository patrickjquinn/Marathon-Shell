#pragma once

#include <QDBusConnection>
#include <QHash>
#include <QSet>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QtQmlIntegration/qqmlintegration.h>

#include <functional>

class QDBusMessage;
class QQmlEngine;
class QJSEngine;

// Android apps as Settings shows them, from deckardd's org.marathonos.Deckard1
// and org.marathonos.Deckard1.Packages (Marathon-Deckard protocol/bridge.md).
class AndroidApps : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QVariantMap runtime READ runtime NOTIFY runtimeChanged)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)

  public:
    static AndroidApps *create(QQmlEngine *engine, QJSEngine *);
    explicit AndroidApps(QObject *parent = nullptr);

    bool         available() const;
    QVariantMap  runtime() const;
    QVariantList apps() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshRuntime();
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setStartAtLogin(bool enabled);
    Q_INVOKABLE void resetAndroid();

    Q_INVOKABLE void loadApp(const QString &pkg);
    // permission: a Marathon permission name ("camera", "storage", "notifications", …).
    Q_INVOKABLE void setPermission(const QString &pkg, const QString &permission, bool granted);
    Q_INVOKABLE void loadPermissionApps(const QString &permission);
    Q_INVOKABLE void setNotifications(const QString &pkg, bool enabled);
    Q_INVOKABLE void setOpenLinks(const QString &pkg, bool enabled);
    Q_INVOKABLE void setBattery(const QString &pkg, const QString &mode);
    Q_INVOKABLE void forceStop(const QString &pkg);
    Q_INVOKABLE void clearCache(const QString &pkg);
    Q_INVOKABLE void clearData(const QString &pkg);
    Q_INVOKABLE void uninstall(const QString &pkg);

    Q_INVOKABLE void loadSpecialAccess(const QString &kind);
    Q_INVOKABLE void setSpecialAccess(const QString &kind, const QString &pkg, bool granted);

  Q_SIGNALS:
    void availableChanged();
    void runtimeChanged();
    void appsChanged();
    void appLoaded(const QString &pkg, const QVariantMap &app);
    void appChanged(const QString &pkg);
    void appRemoved(const QString &pkg);
    void specialAccessLoaded(const QString &kind, const QVariantList &apps);
    void permissionAppsLoaded(const QString &permission, const QVariantList &apps);
    // action: the method's name ("clearData", "uninstall", ...).
    void done(const QString &pkg, const QString &action);
    void failed(const QString &pkg, const QString &action, const QString &error);

  private Q_SLOTS:
    void onRuntimeChanged(const QVariantMap &runtime);
    void onAppChanged(const QString &pkg);
    void onPackageChanged(const QString &pkg, const QString &change);
    void onFinished(const QString &job, bool ok, const QString &pkg, const QString &message);
    void onOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);

  private:
    using Reply = std::function<void(const QDBusMessage &)>;

    void call(const QString &interface, const QString &method, const QVariantList &args, Reply reply);
    void act(const QString &action, const QString &pkg, const QString &method, const QVariantList &args);
    void loadIcon(const QString &pkg);
    void setAvailable(bool available);

    QDBusConnection         m_bus;
    bool                    m_available = false;
    QVariantMap             m_runtime;
    QVariantList            m_apps;
    QHash<QString, QString> m_icons;
    QHash<QString, QString> m_jobs;         // uninstall job → package
    QSet<QString>           m_uninstalling; // asked, not yet answered
};
