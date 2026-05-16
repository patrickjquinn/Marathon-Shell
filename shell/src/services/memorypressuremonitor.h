#pragma once

#include <QObject>
#include <QTimer>

// Polls /proc/pressure/memory and emits when the kernel reports significant
// memory stall. PSI is a Linux 4.20+ feature; on systems without it (or
// without read permission), the monitor stays silent.
//
// Phase B ships this in observe-only mode: we LOG when pressure is high
// and signal the lifecycle layer, but do not kill anything yet. The
// systemd-oomd cgroup config provides the actual killer until we wire a
// targeted SIGTERM/SIGKILL of the oldest Frozen app in a follow-up.
class MemoryPressureMonitor : public QObject {
    Q_OBJECT

  public:
    enum PressureLevel {
        Normal   = 0,
        Moderate = 1,
        High     = 2,
        Critical = 3,
    };
    Q_ENUM(PressureLevel)

    explicit MemoryPressureMonitor(QObject *parent = nullptr);

    bool isAvailable() const {
        return m_available;
    }
    double currentAvg10() const {
        return m_lastAvg10;
    }
    PressureLevel currentLevel() const {
        return m_lastLevel;
    }

  signals:
    void pressureLevelChanged(PressureLevel level, double avg10);

  private:
    void          poll();
    PressureLevel classify(double avg10) const;

    bool          m_available = false;
    QTimer        m_pollTimer;
    double        m_lastAvg10 = 0.0;
    PressureLevel m_lastLevel = Normal;
};
