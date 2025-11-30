#pragma once

#include <QObject>
#include <QString>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QHash>
#include "marathonappregistry.h"

class MarathonAppLoader : public QObject {
    Q_OBJECT

  public:
    explicit MarathonAppLoader(MarathonAppRegistry *registry, QQmlEngine *engine,
                               QObject *parent = nullptr);
    ~MarathonAppLoader() override;

    bool processIsolationEnabled() const {
        return m_processIsolationEnabled;
    }
    void                 setProcessIsolationEnabled(bool enabled);

    Q_INVOKABLE QObject *loadApp(const QString &appId);
    Q_INVOKABLE void     loadAppAsync(const QString &appId); // New async method
    Q_INVOKABLE void     unloadApp(const QString &appId);
    Q_INVOKABLE bool     isAppLoaded(const QString &appId) const;
    Q_INVOKABLE void     preloadApp(const QString &appId);

  signals:
    void appLoaded(const QString &appId);
    void loadError(const QString &appId, const QString &error);
    void appUnloaded(const QString &appId);
    void appLoadProgress(const QString &appId, int percent);        // New progress signal
    void appInstanceReady(const QString &appId, QObject *instance); // New async completion
    void processIsolationEnabledChanged();

  private:
    MarathonAppRegistry                       *m_registry;
    QQmlEngine                                *m_engine;
    QHash<QString, QQmlComponent *>            m_components;
    QHash<QString, class MarathonAppProcess *> m_processes;
    bool                                       m_processIsolationEnabled;

    void     handleComponentStatusAsync(const QString &appId, QQmlComponent *component);
    QObject *createAppInstance(const QString &appId, QQmlComponent *component);
    bool     shouldUseProcessIsolation(const QString &appId) const;
};
