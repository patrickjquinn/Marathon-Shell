#include "memorypressuremonitor.h"

#include <QFile>
#include <QLoggingCategory>
#include <utility>   // std::as_const

Q_LOGGING_CATEGORY(lcPSI, "marathon.lifecycle.pressure")

// PSI thresholds, in percent-of-time-stalled within a 10s window. Tuned
// conservatively for a memory-constrained mobile device (4GB):
//   Normal   < 5%
//   Moderate 5–20%   — backgrounded apps are getting paged out
//   High     20–40%  — kernel is reclaiming aggressively, consider
//                      proactively killing oldest Frozen app (later)
//   Critical >40%    — system close to OOM; kernel/oomd will act soon
static constexpr double kModerate       = 5.0;
static constexpr double kHigh           = 20.0;
static constexpr double kCritical       = 40.0;
static constexpr int    kPollIntervalMs = 5000;

MemoryPressureMonitor::MemoryPressureMonitor(QObject *parent)
    : QObject(parent) {
    QFile probe(QStringLiteral("/proc/pressure/memory"));
    if (!probe.exists()) {
        qCInfo(lcPSI) << "PSI not present in this kernel; pressure monitoring disabled";
        return;
    }
    if (!probe.open(QIODevice::ReadOnly)) {
        qCInfo(lcPSI) << "PSI not readable (need CONFIG_PSI=y + accessible procfs);"
                      << "pressure monitoring disabled:" << probe.errorString();
        return;
    }
    probe.close();
    m_available = true;

    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, &QTimer::timeout, this, &MemoryPressureMonitor::poll);
    m_pollTimer.start();
    poll();
    qCInfo(lcPSI) << "memory pressure monitor armed, poll interval" << kPollIntervalMs << "ms";
}

void MemoryPressureMonitor::poll() {
    QFile f(QStringLiteral("/proc/pressure/memory"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QByteArray data = f.readAll();
    f.close();

    // Format we care about:
    //   some avg10=12.34 avg60=... avg300=... total=...
    // The "some" line is "any task stalled"; the "full" line is "all tasks
    // stalled" (i.e. nobody can make progress). "some" is the right metric
    // for "backgrounded apps about to be killed" — full means we're past
    // that point already.
    const auto lines = data.split('\n');
    for (const QByteArray &line : lines) {
        if (!line.startsWith("some "))
            continue;
        const int idx = line.indexOf("avg10=");
        if (idx < 0)
            break;
        const int start = idx + 6;
        int       end   = line.indexOf(' ', start);
        if (end < 0)
            end = line.size();
        bool         ok    = false;
        const double avg10 = QString::fromLatin1(line.mid(start, end - start)).toDouble(&ok);
        if (!ok)
            break;
        m_lastAvg10             = avg10;
        const PressureLevel lvl = classify(avg10);
        if (lvl != m_lastLevel) {
            qCInfo(lcPSI) << "level →" << static_cast<int>(lvl) << "(avg10=" << avg10 << "%)";
            m_lastLevel = lvl;
            emit pressureLevelChanged(lvl, avg10);
        }
        break;
    }
}

MemoryPressureMonitor::PressureLevel MemoryPressureMonitor::classify(double avg10) const {
    if (avg10 >= kCritical)
        return Critical;
    if (avg10 >= kHigh)
        return High;
    if (avg10 >= kModerate)
        return Moderate;
    return Normal;
}
