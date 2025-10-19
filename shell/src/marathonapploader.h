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
    explicit MarathonAppLoader(MarathonAppRegistry *registry, QQmlEngine *engine, QObject *parent = nullptr);
    ~MarathonAppLoader() override;
    
    Q_INVOKABLE QObject* loadApp(const QString &appId);
    Q_INVOKABLE void unloadApp(const QString &appId);
    Q_INVOKABLE bool isAppLoaded(const QString &appId) const;
    Q_INVOKABLE void preloadApp(const QString &appId);
    
signals:
    void appLoaded(const QString &appId);
    void loadError(const QString &appId, const QString &error);
    void appUnloaded(const QString &appId);
    
private:
    MarathonAppRegistry *m_registry;
    QQmlEngine *m_engine;
    QHash<QString, QQmlComponent*> m_components;
};

