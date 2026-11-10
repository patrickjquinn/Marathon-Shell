// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The app's action runtime (ADR-0018, decision 5): every declaration
// registers here; calls (from D-Bus, from QML's KeelActions singleton or
// from KeelAction.invoke()) are validated against the manifest's schemas
// and dispatched to the declaration, or to a native (Rust) function.
//
// The manifest is the generated actions.json: compiled into the app (the
// symbol keel_actions_manifest, found in any loaded object), or the file
// named by KEEL_ACTIONS_MANIFEST. Without one, schemas come from the live
// declarations (describe()), which is what tests and `keel run` see before
// the build step has run.
#ifndef KEEL_ACTIONS_REGISTRY_H
#define KEEL_ACTIONS_REGISTRY_H

#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <functional>

class KeelAction;
class KeelCall;
class KeelContext;
class KeelEntity;
class KeelPage;
class KeelShortcut;
class QJSEngine;
class QQmlEngine;

class KeelActionRegistry : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(KeelActions)
    QML_SINGLETON
    Q_PROPERTY(QString appId READ appId NOTIFY appIdChanged)
    // Started for D-Bus activation (--keel-actions or KEEL_ACTIONS_HEADLESS=1):
    // the window stays hidden and the process quits when idle, until app.show
    // shows it.
    Q_PROPERTY(bool headless READ headless NOTIFY headlessChanged)

public:
    static KeelActionRegistry *instance();
    static KeelActionRegistry *create(QQmlEngine *, QJSEngine *);

    QString appId() const;
    void setAppId(const QString &appId);
    bool headless() const { return m_headless; }

    // The generated manifest, if the app has one (empty object otherwise).
    QJsonObject manifest() const { return m_manifest; }
    void setManifest(const QJsonObject &manifest);
    // The manifest built from the live declarations.
    Q_INVOKABLE QJsonObject describe() const;
    // The manifest the runtime enforces: the generated one, else describe().
    QJsonObject effectiveManifest() const;
    // Tool entry for an action / find tool, by action name ("notes.create").
    QJsonObject tool(const QString &action) const;

    // Calls, as D-Bus does. `options`: userInitiated (bool). The D-Bus
    // adaptor passes userInitiated only from a trusted sender
    // (keelcallertrust.h); in-process callers are the app itself.
    Q_INVOKABLE KeelCall *invoke(const QString &action, const QVariantMap &arguments,
                                 const QVariantMap &options = QVariantMap());
    Q_INVOKABLE KeelCall *getEntity(const QString &type, const QString &id);
    Q_INVOKABLE KeelCall *findEntities(const QString &type, const QString &query, int limit = 10);
    // The active page's context, or an empty object when there is none or the
    // app has not been in the foreground in the last 30 s.
    Q_INVOKABLE QJsonObject context() const;

    void addAction(KeelAction *action);
    void removeAction(KeelAction *action);
    void addEntity(KeelEntity *entity);
    void removeEntity(KeelEntity *entity);
    void addContext(KeelContext *context);
    void removeContext(KeelContext *context);
    void addShortcut(KeelShortcut *shortcut);
    void removeShortcut(KeelShortcut *shortcut);
    void addPage(KeelPage *page);
    void removePage(KeelPage *page);

    // The built-in app.show for the pages registered now (the generator's
    // show_action() in keel/actions/schema/src/decl.rs; change both together).
    static constexpr const char *ShowAction = "app.show";
    QJsonObject showTool() const;

    // Shared by KeelAction::invoke() and invoke(): validation, routing and
    // the result check.
    void start(KeelCall *call, KeelAction *target);

    // Serves org.shipwright.Keel.Actions on the session bus, when the app
    // has a manifest (or KEEL_ACTIONS_DBUS=1). Once; called when the
    // plugin is loaded.
    void serve();

    // Milliseconds a call for a declared action waits for its declaration to
    // register (activation runs before the QML has loaded).
    static constexpr int RegistrationWaitMs = 10000;
    // Foreground window within which context() answers.
    static constexpr int ContextForegroundMs = 30000;

Q_SIGNALS:
    void appIdChanged();
    void headlessChanged();
    // A call started or finished (the idle timer of headless mode listens).
    void activity();

private:
    explicit KeelActionRegistry(QObject *parent = nullptr);
    void loadManifest();
    void trackApplicationState();
    bool declared(const QString &action) const;
    void flushPending(const QString &action);
    bool startNative(KeelCall *call);
    // app.show: shows the window if D-Bus activation kept it hidden, opens
    // the page asked for and raises the app.
    void show(KeelCall *call);
    void openPage(KeelPage *page, KeelCall *call);
    void leaveHeadless();
    static void raiseWindow();
    QJsonObject entityEntry(const QString &type) const;

    QString m_appId;
    bool m_headless = false;
    QJsonObject m_manifest;
    QHash<QString, QPointer<KeelAction>> m_actions;
    QHash<QString, QPointer<KeelEntity>> m_entities;
    QList<QPointer<KeelContext>> m_contexts;
    QList<QPointer<KeelShortcut>> m_shortcuts;
    QHash<QString, QPointer<KeelPage>> m_pages;
    // app.show calls waiting for their page to register.
    QList<QPointer<KeelCall>> m_pendingPages;
    // Calls waiting for their action to register.
    QList<QPointer<KeelCall>> m_pending;
    // Entity lookups and searches waiting for their entity type to
    // register (activation can answer before the QML has loaded it).
    struct PendingEntityCall {
        QString type;
        QPointer<KeelCall> call;
        std::function<void(KeelEntity *)> run;
    };
    QList<PendingEntityCall> m_pendingEntities;
    void waitForEntity(const QString &type, KeelCall *call, std::function<void(KeelEntity *)> run);
    bool m_foreground = false;
    bool m_serving = false;
    QElapsedTimer m_sinceBackground;
};

#endif
