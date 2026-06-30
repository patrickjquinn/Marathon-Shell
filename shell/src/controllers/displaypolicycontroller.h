#pragma once

#include <QObject>
#include <qqml.h>

class DisplayManagerCpp;
class SettingsManager;

class DisplayPolicyController : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(DisplayPolicyControllerCpp)
    QML_SINGLETON
    Q_PROPERTY(int screenTimeoutMs READ screenTimeoutMs WRITE setScreenTimeoutMs NOTIFY
                   screenTimeoutMsChanged)
    Q_PROPERTY(QString screenTimeoutString READ screenTimeoutString NOTIFY screenTimeoutMsChanged)
    Q_PROPERTY(bool autoBrightnessEnabled READ autoBrightnessEnabled WRITE setAutoBrightnessEnabled
                   NOTIFY autoBrightnessEnabledChanged)
    Q_PROPERTY(bool screenOn READ screenOn NOTIFY screenOnChanged)

  public:
    explicit DisplayPolicyController(DisplayManagerCpp *displayManager,
                                     SettingsManager *settingsManager, QObject *parent = nullptr);

    int     screenTimeoutMs() const;
    void    setScreenTimeoutMs(int ms);

    QString screenTimeoutString() const;

    bool    autoBrightnessEnabled() const;
    void    setAutoBrightnessEnabled(bool enabled);

    bool    screenOn() const {
        return m_screenOn;
    }

    Q_INVOKABLE void turnScreenOn();
    Q_INVOKABLE void turnScreenOff();

    // Force-unblank path for the resume-from-suspend edge. External
    // suspends (logind IdleAction, lid switch, RTC alarm, anything not
    // going through PowerPolicyController::sleep) never observe a
    // screen-off transition in the shell — so m_screenOn stays stale
    // TRUE across the sleep, and turnScreenOn() short-circuits its
    // screenOnChanged emit. forceScreenOn() unconditionally re-issues
    // setScreenState(true) (which re-writes bl_power AND brightness)
    // and ALWAYS emits screenOnChanged so QML hooks (dimState.restore,
    // idleScreenTimer.restart) fire on the wake edge.
    Q_INVOKABLE void forceScreenOn();

  signals:
    void screenTimeoutMsChanged();
    void autoBrightnessEnabledChanged();
    void screenOnChanged();

  private:
    DisplayManagerCpp *m_displayManager  = nullptr;
    SettingsManager   *m_settingsManager = nullptr;
    bool               m_screenOn        = true;
};
