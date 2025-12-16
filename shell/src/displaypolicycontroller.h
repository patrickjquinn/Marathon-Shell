#pragma once

#include <QObject>

class DisplayManagerCpp;
class SettingsManager;

/**
 * DisplayPolicyController
 *
 * Owns display-related policy/glue that should not live in QML:
 * - syncing user preferences (SettingsManager) <-> hardware backend (DisplayManagerCpp)
 * - screen on/off state tracking
 * - screen timeout ms API + display string formatting
 */
class DisplayPolicyController : public QObject {
    Q_OBJECT
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

  signals:
    void screenTimeoutMsChanged();
    void autoBrightnessEnabledChanged();
    void screenOnChanged();

  private:
    DisplayManagerCpp *m_displayManager  = nullptr;
    SettingsManager   *m_settingsManager = nullptr;
    bool               m_screenOn        = true;
};
