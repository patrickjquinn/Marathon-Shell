#include "motiondaemon.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QRandomGenerator>

extern "C" {
#include <StepCountingAlgo.h>
}

// 50 Hz IIO sampling. Lower than typical wearable rates (100–200 Hz)
// but plenty for Oxford's algorithm (the ringbuffer averages magnitude
// over a 0.4 s window) and keeps the CPU duty cycle gentle on
// phone-class SoCs where Marathon runs.
namespace {
    constexpr int kSampleHz       = 50;
    constexpr int kSampleMs       = 1000 / kSampleHz;
    constexpr int kMinuteMs       = 60 * 1000;
    constexpr int kActiveStepsMin = 100; // ≥ 100 steps/minute = walking
    constexpr int kStandStepsMin  = 30;  // ≥ 30 steps in any minute of an hour ⇒ "stood"
} // namespace

MotionDaemon::MotionDaemon(QObject *parent)
    : QObject(parent)
    , m_today(QDate::currentDate()) {
    ::initAlgo();

    m_demoMode = qEnvironmentVariableIntValue("MARATHON_MOTION_DEMO") != 0;
    if (!m_demoMode) {
        m_available = detectIioAccelerometer();
    } else {
        m_available = true;
        qInfo() << "[MotionDaemon] Demo mode — synthesizing activity rings";
    }

    if (!m_available && !m_demoMode) {
        qInfo() << "[MotionDaemon] No IIO accelerometer found; activity rings disabled. Set "
                   "MARATHON_MOTION_DEMO=1 to test the UI.";
        return;
    }

    m_sampleTimer.setInterval(kSampleMs);
    m_sampleTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_sampleTimer, &QTimer::timeout, this, &MotionDaemon::onSampleTick);

    m_minuteTimer.setInterval(kMinuteMs);
    m_minuteTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_minuteTimer, &QTimer::timeout, this, &MotionDaemon::onMinuteTick);

    m_sampleTimer.start();
    m_minuteTimer.start();
    qInfo() << "[MotionDaemon] Started (source:" << (m_demoMode ? "demo" : m_iioBaseDir) << ")";
}

MotionDaemon::~MotionDaemon() = default;

double MotionDaemon::movePercent() const {
    if (m_moveGoal <= 0)
        return 0.0;
    return qBound(0.0, double(m_stepsToday) / double(m_moveGoal), 1.0);
}

double MotionDaemon::exercisePercent() const {
    if (m_exerciseGoal <= 0)
        return 0.0;
    return qBound(0.0, double(m_activeMinutes) / double(m_exerciseGoal), 1.0);
}

double MotionDaemon::standPercent() const {
    if (m_standGoal <= 0)
        return 0.0;
    return qBound(0.0, double(m_standHours) / double(m_standGoal), 1.0);
}

void MotionDaemon::reset() {
    ::resetAlgo();
    m_stepsToday        = 0;
    m_activeMinutes     = 0;
    m_standHours        = 0;
    m_stepsAtMidnight   = 0;
    m_stepsAtLastMinute = 0;
    for (int i = 0; i < 24; i++) {
        m_minuteSteps[i] = 0;
        m_hourStood[i]   = false;
    }
    emit ringsChanged();
}

bool MotionDaemon::detectIioAccelerometer() {
    // Scan /sys/bus/iio/devices/iio:device* for the first device that
    // exposes in_accel_{x,y,z}_raw. PinePhone (MPU6050), SDM845
    // (BMI160), and Pinephone Pro (LSM6DSO) all expose this pattern.
    QDir base("/sys/bus/iio/devices");
    if (!base.exists())
        return false;
    const QStringList devs = base.entryList(QStringList() << "iio:device*", QDir::Dirs);
    for (const QString &d : devs) {
        const QString p = base.filePath(d);
        if (QFile::exists(p + "/in_accel_x_raw") && QFile::exists(p + "/in_accel_y_raw") &&
            QFile::exists(p + "/in_accel_z_raw")) {
            m_iioBaseDir = p;
            return true;
        }
    }
    return false;
}

bool MotionDaemon::readIioSample(int &x, int &y, int &z) {
    auto read = [&](const QString &axis, int &out) {
        QFile f(m_iioBaseDir + "/in_accel_" + axis + "_raw");
        if (!f.open(QIODevice::ReadOnly))
            return false;
        out = f.readAll().trimmed().toInt();
        return true;
    };
    return read("x", x) && read("y", y) && read("z", z);
}

void MotionDaemon::feedSample(qint64 timeMs, int x, int y, int z) {
    ::processSample(static_cast<int32_t>(timeMs), static_cast<int16_t>(x), static_cast<int16_t>(y),
                    static_cast<int16_t>(z));
    const int newSteps = static_cast<int>(::getSteps());
    if (newSteps != m_stepsToday - m_stepsAtMidnight) {
        m_stepsToday = m_stepsAtMidnight + newSteps;
        emit ringsChanged();
    }
}

void MotionDaemon::onSampleTick() {
    rollDayIfNeeded();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();

    if (m_demoMode) {
        // Synthesize a brisk walking sinusoid centred on -1 g vertical
        // with peak-to-peak ≥ Oxford's MOTION_THRESHOLD (500) so the
        // algorithm leaves the no-motion path. Frequency is ~1 step
        // per 0.6 s ≈ 100 spm — fast enough to register exercise
        // minutes once the warmup window passes.
        const double t   = double(now) / 1000.0;
        const double phi = t * 10.0; // ~1 step / 0.63 s
        const int    z   = static_cast<int>(-980 + 600 * std::sin(phi));
        const int    x   = static_cast<int>(300 * std::sin(phi * 0.5));
        const int    y   = static_cast<int>(250 * std::cos(phi * 0.5));
        feedSample(now, x, y, z);
        return;
    }

    int x = 0, y = 0, z = 0;
    if (readIioSample(x, y, z))
        feedSample(now, x, y, z);
}

void MotionDaemon::onMinuteTick() {
    rollDayIfNeeded();
    const QTime t       = QTime::currentTime();
    const int   hourIdx = t.hour();
    const int   delta   = qMax(0, m_stepsToday - m_stepsAtLastMinute);
    m_stepsAtLastMinute = m_stepsToday;
    m_minuteSteps[hourIdx] += delta;

    if (delta >= kActiveStepsMin) {
        m_activeMinutes += 1;
    }

    if (delta >= kStandStepsMin && !m_hourStood[hourIdx]) {
        m_hourStood[hourIdx] = true;
        m_standHours += 1;
    }
    emit ringsChanged();
}

void MotionDaemon::rollDayIfNeeded() {
    const QDate today = QDate::currentDate();
    if (today != m_today) {
        m_today             = today;
        m_stepsAtMidnight   = m_stepsToday;
        m_stepsToday        = 0;
        m_stepsAtLastMinute = 0;
        m_activeMinutes     = 0;
        m_standHours        = 0;
        for (int i = 0; i < 24; i++) {
            m_minuteSteps[i] = 0;
            m_hourStood[i]   = false;
        }
        ::resetSteps();
        emit ringsChanged();
    }
}
