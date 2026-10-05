#include "motiondaemon.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QRandomGenerator>

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

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
    // While the accelerometer refuses reads (iio-sensor-proxy holding its
    // buffer makes direct reads fail with EBUSY), retry once a second
    // instead of failing 50 times a second.
    constexpr int kRetryMs = 1000;
} // namespace

// Samples the accelerometer and runs the step algorithm on its own thread,
// so the 50 Hz reads never stall the shell's GUI thread. The Oxford
// algorithm keeps global state, so every call into it happens here.
class AccelSampler : public QObject {
    Q_OBJECT

  public:
    AccelSampler(const QString &iioBaseDir, bool demoMode)
        : m_iioBaseDir(iioBaseDir)
        , m_demoMode(demoMode) {}

    ~AccelSampler() override {
        for (int fd : m_fds) {
            if (fd >= 0)
                ::close(fd);
        }
    }

  public slots:
    void start() {
        if (!m_demoMode) {
            // Keep the sysfs files open and re-read them with pread rather
            // than opening three files per sample.
            const char *axes[] = {"x", "y", "z"};
            for (int i = 0; i < 3; i++) {
                const QByteArray path =
                    QFile::encodeName(m_iioBaseDir + "/in_accel_" + axes[i] + "_raw");
                m_fds[i] = ::open(path.constData(), O_RDONLY | O_CLOEXEC);
                if (m_fds[i] < 0) {
                    qWarning() << "[MotionDaemon] Cannot open" << path << strerror(errno);
                    return;
                }
            }
        }
        m_timer = new QTimer(this);
        m_timer->setTimerType(Qt::CoarseTimer);
        connect(m_timer, &QTimer::timeout, this, &AccelSampler::tick);
        m_timer->start(kSampleMs);
    }

    void resetAlgo() {
        ::resetAlgo();
        m_lastSteps = 0;
    }

    void resetSteps() {
        ::resetSteps();
        m_lastSteps = 0;
    }

  signals:
    void stepsChanged(int algoSteps);

  private:
    bool readAxis(int fd, int &out) {
        char          buf[16];
        const ssize_t n = ::pread(fd, buf, sizeof(buf) - 1, 0);
        if (n <= 0)
            return false;
        buf[n]    = '\0';
        char *end = nullptr;
        out       = static_cast<int>(strtol(buf, &end, 10));
        return end != buf;
    }

    void tick() {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        int          x = 0, y = 0, z = 0;

        if (m_demoMode) {
            // Synthesize a brisk walking sinusoid centred on -1 g vertical
            // with peak-to-peak ≥ Oxford's MOTION_THRESHOLD (500) so the
            // algorithm leaves the no-motion path. Frequency is ~1 step
            // per 0.6 s ≈ 100 spm — fast enough to register exercise
            // minutes once the warmup window passes.
            const double t   = double(now) / 1000.0;
            const double phi = t * 10.0; // ~1 step / 0.63 s
            z                = static_cast<int>(-980 + 600 * std::sin(phi));
            x                = static_cast<int>(300 * std::sin(phi * 0.5));
            y                = static_cast<int>(250 * std::cos(phi * 0.5));
        } else {
            const bool ok = readAxis(m_fds[0], x) && readAxis(m_fds[1], y) &&
                readAxis(m_fds[2], z);
            m_timer->setInterval(ok ? kSampleMs : kRetryMs);
            if (!ok)
                return;
        }

        ::processSample(static_cast<int32_t>(now), static_cast<int16_t>(x),
                        static_cast<int16_t>(y), static_cast<int16_t>(z));
        const int steps = static_cast<int>(::getSteps());
        if (steps != m_lastSteps) {
            m_lastSteps = steps;
            emit stepsChanged(steps);
        }
    }

    const QString m_iioBaseDir;
    const bool    m_demoMode;
    int           m_fds[3]    = {-1, -1, -1};
    QTimer       *m_timer     = nullptr;
    int           m_lastSteps = 0;
};

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

    m_sampler = new AccelSampler(m_iioBaseDir, m_demoMode);
    m_sampler->moveToThread(&m_samplerThread);
    connect(&m_samplerThread, &QThread::started, m_sampler, &AccelSampler::start);
    connect(&m_samplerThread, &QThread::finished, m_sampler, &QObject::deleteLater);
    connect(m_sampler, &AccelSampler::stepsChanged, this, &MotionDaemon::onStepsChanged);
    m_samplerThread.setObjectName(QStringLiteral("MotionSampler"));

    m_minuteTimer.setInterval(kMinuteMs);
    m_minuteTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_minuteTimer, &QTimer::timeout, this, &MotionDaemon::onMinuteTick);

    m_samplerThread.start(QThread::LowPriority);
    m_minuteTimer.start();
    qInfo() << "[MotionDaemon] Started (source:" << (m_demoMode ? "demo" : m_iioBaseDir) << ")";
}

MotionDaemon::~MotionDaemon() {
    m_samplerThread.quit();
    m_samplerThread.wait();
}

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
    if (m_sampler)
        QMetaObject::invokeMethod(m_sampler, &AccelSampler::resetAlgo, Qt::QueuedConnection);
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

void MotionDaemon::onStepsChanged(int algoSteps) {
    m_stepsToday = m_stepsAtMidnight + algoSteps;
    emit ringsChanged();
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
        if (m_sampler)
            QMetaObject::invokeMethod(m_sampler, &AccelSampler::resetSteps,
                                      Qt::QueuedConnection);
        emit ringsChanged();
    }
}

#include "motiondaemon.moc"
