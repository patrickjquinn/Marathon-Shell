#ifndef DISPLAYMANAGERCPP_H
#define DISPLAYMANAGERCPP_H

#include <QObject>
#include <QString>

class PowerManagerCpp;
class RotationManager;

class DisplayManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool autoBrightnessEnabled READ autoBrightnessEnabled WRITE setAutoBrightness NOTIFY
                   autoBrightnessEnabledChanged)
    Q_PROPERTY(
        bool rotationLocked READ rotationLocked WRITE setRotationLock NOTIFY rotationLockedChanged)
    Q_PROPERTY(
        int screenTimeout READ screenTimeout WRITE setScreenTimeout NOTIFY screenTimeoutChanged)
    Q_PROPERTY(QString screenTimeoutString READ screenTimeoutString NOTIFY screenTimeoutChanged)
    Q_PROPERTY(double brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(bool nightLightEnabled READ nightLightEnabled WRITE setNightLightEnabled NOTIFY
                   nightLightEnabledChanged)
    Q_PROPERTY(int nightLightTemperature READ nightLightTemperature WRITE setNightLightTemperature
                   NOTIFY nightLightTemperatureChanged)
    Q_PROPERTY(QString nightLightSchedule READ nightLightSchedule WRITE setNightLightSchedule NOTIFY
                   nightLightScheduleChanged)

  public:
    explicit DisplayManagerCpp(PowerManagerCpp *powerManager, RotationManager *rotationManager,
                               QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool autoBrightnessEnabled() const {
        return m_autoBrightnessEnabled;
    }
    bool rotationLocked() const {
        return m_rotationLocked;
    }
    int screenTimeout() const {
        return m_screenTimeout;
    }
    QString screenTimeoutString() const;
    double  brightness() const {
        return m_brightness;
    }
    bool nightLightEnabled() const {
        return m_nightLightEnabled;
    }
    int nightLightTemperature() const {
        return m_nightLightTemperature;
    }
    QString nightLightSchedule() const {
        return m_nightLightSchedule;
    }

    void               setBrightness(double brightness);
    Q_INVOKABLE double getBrightness(); // Read current brightness
    Q_INVOKABLE void   setScreenState(bool on);
    Q_INVOKABLE void   setAutoBrightness(bool enabled);
    Q_INVOKABLE void   setRotationLock(bool locked);
    Q_INVOKABLE void   setScreenTimeout(int seconds);
    Q_INVOKABLE void   setNightLightEnabled(bool enabled);
    Q_INVOKABLE void   setNightLightTemperature(int temperature);
    Q_INVOKABLE void   setNightLightSchedule(const QString &schedule);

  signals:
    void availableChanged();
    void autoBrightnessEnabledChanged();
    void rotationLockedChanged();
    void screenTimeoutChanged();
    void brightnessChanged();
    void nightLightEnabledChanged();
    void nightLightTemperatureChanged();
    void nightLightScheduleChanged();
    void screenStateChanged(bool on);

  private:
    bool             m_available;
    QString          m_backlightDevice;
    int              m_maxBrightness;
    bool             m_autoBrightnessEnabled;
    bool             m_rotationLocked;
    int              m_screenTimeout; // in seconds
    double           m_brightness;
    bool             m_nightLightEnabled;
    int              m_nightLightTemperature; // 2700K (warm) to 6500K (cool)
    QString          m_nightLightSchedule;    // "off", "manual", "sunset", "custom"
    PowerManagerCpp *m_powerManager;          // For wakelock management
    RotationManager *m_rotationManager;       // For rotation lock

    bool             detectBacklightDevice();
    void             loadSettings();
    void             saveSettings();
    void             setupBrightnessMonitoring();
    void             pollBrightness(); // Fallback method

  private slots:
    void onExternalBrightnessChanged();
    void onDBusPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                 const QStringList &invalidated);
};

#endif // DISPLAYMANAGERCPP_H
