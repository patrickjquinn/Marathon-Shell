#ifndef DISPLAYMANAGERCPP_H
#define DISPLAYMANAGERCPP_H

#include <QObject>
#include <QString>
#include <qqml.h>

class PowerManagerCpp;
class RotationManager;
class SensorManagerCpp;
class QTimer;

class DisplayManagerCpp : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
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

    void setSensorManager(SensorManagerCpp *sensorManager);

    // Lightweight call-scoped backlight blank driven by the proximity
    // sensor while a voice call is active (owned by TelephonyIntegration).
    // NOT the deep-idle Doze — just powers the backlight LED down/up so
    // moving the phone to/from your ear toggles the panel instantly.
    Q_INVOKABLE void setCallProximityBlank(bool blank);

    bool             available() const {
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
    double  brightness() const;
    bool    nightLightEnabled() const {
        return m_nightLightEnabled;
    }
    int nightLightTemperature() const {
        return m_nightLightTemperature;
    }
    QString nightLightSchedule() const {
        return m_nightLightSchedule;
    }

    void               setBrightness(double brightness);
    Q_INVOKABLE double getBrightness();
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
    // Power-cycle the backlight LED to a lit state. Must be called AFTER
    // the compositor has re-enabled the CRTC on wake (see setScreenState).
    void forceBacklightOn();

    // --- Adaptive brightness engine ---------------------------------
    // Map an ambient-light reading (lux) to a user-space [0,1] target
    // via a perceptual (log) curve, apply asymmetric hysteresis so we
    // only react to sustained changes, and ease toward the target with
    // a smooth PWM ramp instead of an instant jump.
    double            luxToUserBrightness(double lux) const;
    void              startBrightnessRamp(double targetUser);
    void              rampStep();

    double            m_luxEwma         = -1.0; // smoothed lux (-1 = unseeded)
    double            m_autoTargetUser  = -1.0; // last auto target committed
    qint64            m_luxAboveSinceMs = 0;    // dwell timers for hysteresis
    qint64            m_luxBelowSinceMs = 0;
    qint64            m_lastManualSetMs = 0; // manual override grace window
    QTimer           *m_rampTimer       = nullptr;
    double            m_rampFromUser    = 0.0;
    double            m_rampToUser      = 0.0;
    qint64            m_rampStartMs     = 0;
    int               m_rampDurationMs  = 600;

    bool              m_proximityBlanked = false;

    bool              m_available;
    QString           m_backlightDevice;
    int               m_maxBrightness;
    bool              m_autoBrightnessEnabled;
    bool              m_rotationLocked;
    int               m_screenTimeout;
    double            m_brightness;
    bool              m_nightLightEnabled;
    int               m_nightLightTemperature;
    QString           m_nightLightSchedule;
    PowerManagerCpp  *m_powerManager;
    RotationManager  *m_rotationManager;
    SensorManagerCpp *m_sensorManager = nullptr;

    bool              detectBacklightDevice();
    void              loadSettings();
    void              saveSettings();
    void              setupBrightnessMonitoring();

  private slots:
    void onExternalBrightnessChanged();
    void onDBusPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                 const QStringList &invalidated);
    void onAmbientLightChanged();
};

#endif
