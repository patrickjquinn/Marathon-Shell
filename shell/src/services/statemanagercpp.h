#ifndef STATEMANAGERCPP_H
#define STATEMANAGERCPP_H

#include <QObject>
#include <QSettings>
#include <QTimer>
#include <QVariantMap>

class StateManagerCpp : public QObject {
    Q_OBJECT

  public:
    explicit StateManagerCpp(QObject *parent = nullptr);

    Q_INVOKABLE void        registerApp(const QString &appId, bool isVisible);
    Q_INVOKABLE void        unregisterApp(const QString &appId);
    Q_INVOKABLE void        updateAppVisibility(const QString &appId, bool isVisible);
    Q_INVOKABLE void        saveAppState(const QString &appId, const QString &state);
    Q_INVOKABLE void        saveAllStates();
    Q_INVOKABLE QStringList restoreStates();
    Q_INVOKABLE QVariantMap getAppState(const QString &appId) const;
    Q_INVOKABLE void        clearAppState(const QString &appId);
    Q_INVOKABLE void        clearAllStates();

  private:
    void        loadStateData();
    void        scheduleAutoSave();
    QVariantMap mapForRunningApp(const QString &appId, bool isVisible) const;
    QVariantMap mapForState(const QString &state) const;

    QSettings   m_settings;
    QVariantMap m_runningApps;
    QVariantMap m_appStates;
    QTimer      m_autoSaveTimer;
};

#endif
