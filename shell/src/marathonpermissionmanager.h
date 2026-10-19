#pragma once

class QQmlEngine;
class QJSEngine;

#include "marathonappregistry.h"
#include "marathonmanifest.h"
#include <QPointer>
#include <QMap>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <qqml.h>

#include <functional>

class MarathonPermissionManager : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(PermissionManager)
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static MarathonPermissionManager *create(QQmlEngine *, QJSEngine *);
    Q_PROPERTY(bool promptActive READ promptActive NOTIFY promptActiveChanged)
    Q_PROPERTY(QString currentAppId READ currentAppId NOTIFY currentRequestChanged)
    Q_PROPERTY(QString currentPermission READ currentPermission NOTIFY currentRequestChanged)
    Q_PROPERTY(QStringList currentPermissions READ currentPermissions NOTIFY currentRequestChanged)
    // Restricted permissions the app declared but cannot hold, shown in the
    // prompt so the user knows they were refused.
    Q_PROPERTY(QStringList currentRefused READ currentRefused NOTIFY currentRequestChanged)
    // Set while the prompt asks for an app whose grants another system
    // keeps (askForeign): its kind and choices.
    Q_PROPERTY(QVariantMap currentOptions READ currentOptions NOTIFY currentRequestChanged)

  public:
    enum PermissionStatus : quint8 {
        NotRequested,
        Granted,
        Denied,
        Prompt
    };
    Q_ENUM(PermissionStatus)

    explicit MarathonPermissionManager(QObject *parent = nullptr);

    // Where the manager learns what each app declared and whether it is a
    // protected system app. Without one only stored decisions count.
    void             setAppRegistry(MarathonAppRegistry *registry);

    Q_INVOKABLE bool hasPermission(const QString &appId, const QString &permission);

    Q_INVOKABLE void requestPermission(const QString &appId, const QString &permission);
    Q_INVOKABLE void requestPermissions(const QString &appId, const QStringList &permissions);
    // Every permission the app declares that is not decided yet, in one
    // prompt: called when it launches.
    void requestDeclaredPermissions(const QString &appId);
    // The prompt's answer for every permission it asks about.
    Q_INVOKABLE void respond(bool granted);
    // The answer with the prompt's choices: for a foreign prompt, "only
    // this time" and precise location.
    Q_INVOKABLE void respondWith(bool granted, bool once, bool precise);

    // "allow", "once", "deny" or "cancel" (dismissed, unanswered).
    using ForeignAnswer = std::function<void(const QString &answer, bool precise)>;
    // A prompt for an app whose permissions are kept elsewhere (an Android
    // app, for deckardd). options: kind (foreground, background, precise),
    // once (offer "only this time"), accuracy ("choice" or "approximate"),
    // preciseDefault. Nothing is stored; done is called once.
    void askForeign(const QString &key, const QString &appId, const QString &permission,
                    const QVariantMap &options, ForeignAnswer done);
    // Answers a waiting or showing foreign prompt "cancel".
    void cancelForeign(const QString &key);
    // For a caller refused all of `permissions`: asks the user for the first
    // the app declared but was never asked about, as iOS does on first use.
    // Returns it, or empty when there is nothing to ask.
    QString          askIfUndecided(const QString &appId, const QStringList &permissions);

    Q_INVOKABLE void setPermission(const QString &appId, const QString &permission, bool granted,
                                   bool remember = true);
    Q_INVOKABLE void setPermissions(const QString &appId, const QStringList &permissions,
                                    bool granted, bool remember = true);

    Q_INVOKABLE void dismissAll();
    // Drop any active or queued prompt belonging to appId. Called when
    // an app-runner exits — without this the shell keeps showing the
    // dead app's dialog over every subsequent foreground app.
    Q_INVOKABLE void             dismissForApp(const QString &appId);
    Q_INVOKABLE QStringList      getAppPermissions(const QString &appId);

    Q_INVOKABLE void             revokePermission(const QString &appId, const QString &permission);
    // Drops every decision for the app, as when it is uninstalled.
    void        forgetApp(const QString &appId);

    Q_INVOKABLE MarathonPermissionManager::PermissionStatus getPermissionStatus(const QString &appId,
                                                     const QString &permission);

    Q_INVOKABLE QStringList      getAvailablePermissions();

    Q_INVOKABLE QString          getPermissionLabel(const QString &permission);
    Q_INVOKABLE QString          getPermissionDescription(const QString &permission);

    bool                         promptActive() const {
        return m_promptActive;
    }
    QString currentAppId() const {
        return m_currentAppId;
    }
    QString currentPermission() const {
        return m_currentPermission;
    }
    QStringList currentPermissions() const {
        return m_currentPermissions;
    }
    QStringList currentRefused() const {
        return m_currentRefused;
    }
    QVariantMap currentOptions() const {
        return m_currentOptions;
    }

  signals:
    void permissionGranted(const QString &appId, const QString &permission);
    void permissionDenied(const QString &appId, const QString &permission);
    void permissionRevoked(const QString &appId, const QString &permission);
    void permissionRequested(const QString &appId, const QString &permission);
    void permissionsRequested(const QString &appId, const QStringList &permissions);
    void promptActiveChanged();
    void currentRequestChanged();

  private slots:
    void processPendingRequests();

  private:
    void    loadPermissions();
    void    savePermissions();
    QString getPermissionsFilePath();
    void    checkQueue();
    void           closePrompt();
    static QString canonical(const QString &permission);
    static bool    declares(const MarathonAppRegistry::AppInfo &app, const QString &permission);
    const MarathonAppRegistry::AppInfo *appInfo(const QString &appId) const;
    bool isRefused(const MarathonAppRegistry::AppInfo *app, const QString &permission) const;

    QPointer<MarathonAppRegistry>               m_registry;
    QMap<QString, QMap<QString, bool>>    m_permissions;

    bool                                  m_promptActive;
    QString                               m_currentAppId;
    QString                               m_currentPermission;
    QStringList                           m_currentPermissions;
    QStringList                                 m_currentRefused;
    QVariantMap                                 m_currentOptions;

    QMap<QString, MarathonManifest::Permission> m_vocabulary;

    class PortalManager                  *m_portalManager;
    class QTimer                         *m_batchTimer;

    struct PendingRequest {
        QString appId;
        QString permission;
    };
    QList<PendingRequest> m_pendingRequests;

    struct ForeignRequest {
        QString       key;
        QString       appId;
        QString       permission;
        QVariantMap   options;
        ForeignAnswer done;
    };
    QList<ForeignRequest> m_foreign;
    QString               m_currentForeign;
    bool                  showForeign();
    void                  finishForeign(const QString &key, const QString &answer, bool precise);
};
