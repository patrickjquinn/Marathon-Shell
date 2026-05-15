#pragma once

#include <QDate>
#include <QObject>
#include <QString>
#include <QTimer>

// MotionDaemon — Apple-Watch-style Activity Rings backend.
//
// Reads accelerometer XYZ samples (typically 50 Hz off
// /sys/bus/iio/devices/iio:device*/in_accel_*_raw on a phone-class
// device exposing the BMI160/MPU6050 family) and feeds them into the
// vendored Oxford C-Step-Counter algorithm. From the step stream we
// derive three rings:
//
//   - Move      : steps vs daily goal (default 6,500)
//   - Exercise  : minutes of sustained activity at ≥ ~100 spm (default 30)
//   - Stand     : 1-minute "stood-up" windows per hour, 12-of-N target
//
// The shell exposes the daemon as `ActivityService` so QML can bind
// to `stepsToday`, `activeMinutes`, `standHours`, plus the three
// ring percentages used by the lock-screen Activity NowBar and the
// Active-Frames Health frame. A small ring buffer of recent
// magnitudes keeps the stand-detector quiet during the screen-off
// blanking periods.
//
// On the dev box (no IIO sensors) the daemon falls back to a demo
// generator that synthesizes a plausible day's worth of motion so
// the rings render for visual validation. Set
// MARATHON_MOTION_DEMO=1 to force this on any device.
class MotionDaemon : public QObject {
    Q_OBJECT
    Q_PROPERTY(int stepsToday READ stepsToday NOTIFY ringsChanged)
    Q_PROPERTY(int activeMinutes READ activeMinutes NOTIFY ringsChanged)
    Q_PROPERTY(int standHours READ standHours NOTIFY ringsChanged)
    Q_PROPERTY(int moveGoal READ moveGoal CONSTANT)
    Q_PROPERTY(int exerciseGoal READ exerciseGoal CONSTANT)
    Q_PROPERTY(int standGoal READ standGoal CONSTANT)
    Q_PROPERTY(double movePercent READ movePercent NOTIFY ringsChanged)
    Q_PROPERTY(double exercisePercent READ exercisePercent NOTIFY ringsChanged)
    Q_PROPERTY(double standPercent READ standPercent NOTIFY ringsChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

  public:
    explicit MotionDaemon(QObject *parent = nullptr);
    ~MotionDaemon() override;

    int stepsToday() const {
        return m_stepsToday;
    }
    int activeMinutes() const {
        return m_activeMinutes;
    }
    int standHours() const {
        return m_standHours;
    }
    int moveGoal() const {
        return m_moveGoal;
    }
    int exerciseGoal() const {
        return m_exerciseGoal;
    }
    int standGoal() const {
        return m_standGoal;
    }
    double movePercent() const;
    double exercisePercent() const;
    double standPercent() const;
    bool   available() const {
        return m_available;
    }

    Q_INVOKABLE void reset();

  signals:
    void ringsChanged();
    void availableChanged();

  private slots:
    void onSampleTick();
    void onMinuteTick();

  private:
    bool detectIioAccelerometer();
    bool readIioSample(int &x, int &y, int &z);
    void feedSample(qint64 timeMs, int x, int y, int z);
    void rollDayIfNeeded();

    // Sources
    QString m_iioBaseDir; // e.g. /sys/bus/iio/devices/iio:device0
    bool    m_available = false;
    bool    m_demoMode  = false;

    // 50 Hz sample timer + 60 s rollup timer
    QTimer m_sampleTimer;
    QTimer m_minuteTimer;

    // Day rollup
    QDate m_today;
    int   m_stepsAtMidnight = 0;

    // Derived ring values (per day so far)
    int m_stepsToday    = 0;
    int m_activeMinutes = 0;
    int m_standHours    = 0;

    // Hourly activity buckets — populated by onMinuteTick (an hour is
    // "stood" if any minute had >= ~30 steps), reset at midnight.
    int  m_minuteSteps[24] = {0};
    bool m_hourStood[24]   = {false};

    // Sliding 60-second step counter (m_stepsToday delta over the
    // last minute) drives the exercise ring.
    int m_stepsAtLastMinute = 0;

    // Goal defaults (eventually pulled from SettingsManager)
    int m_moveGoal     = 6500;
    int m_exerciseGoal = 30;
    int m_standGoal    = 12;
};
