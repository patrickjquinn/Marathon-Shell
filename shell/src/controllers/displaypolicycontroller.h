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

    int              screenTimeoutMs() const;
    void             setScreenTimeoutMs(int ms);

    QString          screenTimeoutString() const;

    bool             autoBrightnessEnabled() const;
    void             setAutoBrightnessEnabled(bool enabled);

    bool             screenOn() const;

    Q_INVOKABLE void turnScreenOn();
    Q_INVOKABLE void turnScreenOff(const QString &reason = QStringLiteral("other"));

    // Force-unblank path for the resume-from-suspend edge. External
    // suspends (logind IdleAction, lid switch, RTC alarm) never turn the
    // screen off in the shell, so the screen still reads on across the
    // sleep. forceScreenOn() re-issues setScreenState(true) (which re-writes
    // bl_power AND brightness) and always emits screenOnChanged so QML hooks
    // (dimState.restore, idleScreenTimer.restart) fire on the wake edge.
    Q_INVOKABLE void forceScreenOn();

  signals:
    void screenTimeoutMsChanged();
    void autoBrightnessEnabledChanged();
    void screenOnChanged();

  private:
    DisplayManagerCpp *m_displayManager  = nullptr;
    SettingsManager   *m_settingsManager = nullptr;
};
