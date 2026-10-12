#include "rtscheduler.h"
#include <QDebug>
#include <QFile>
#include <QTextStream>

#include <sched.h>
#include <sys/resource.h>
#include <pthread.h>

RTScheduler::RTScheduler(QObject *parent)
    : QObject(parent)
    , m_isRealtimeKernel(false) {
    detectKernelCapabilities();
}

void RTScheduler::detectKernelCapabilities() {
    // Two independent capabilities matter here:
    //
    //   (1) SCHED_FIFO permission -- the shell needs CAP_SYS_NICE (or rtprio in
    //       /etc/security/limits.conf) to elevate its compositor/input threads
    //       to SCHED_FIFO. Without this we run on SCHED_OTHER and may drop
    //       frames under heavy CPU load. THIS is what we actually need.
    //
    //   (2) PREEMPT_RT kernel -- bounds worst-case latency for SCHED_FIFO
    //       threads (~280 µs vs ~700 µs under load). For a 60–120 Hz touch UI
    //       with a 8–16 ms frame budget this is well below the noise floor.
    //       postmarketOS, Plasma Mobile, Phosh and Android all ship with
    //       CONFIG_PREEMPT (low-latency, not PREEMPT_RT). It's a nice-to-have
    //       primarily for hard-real-time audio paths.

    // Detect the kernel preemption model -- informational only.
    QFile realtimeFile("/sys/kernel/realtime");
    if (realtimeFile.exists() && realtimeFile.open(QIODevice::ReadOnly)) {
        QTextStream stream(&realtimeFile);
        m_isRealtimeKernel = (stream.readLine().trimmed() == "1");
    } else {
        QFile versionFile("/proc/version");
        if (versionFile.open(QIODevice::ReadOnly)) {
            QTextStream stream(&versionFile);
            m_isRealtimeKernel = stream.readAll().contains("PREEMPT_RT");
        }
    }

    if (m_isRealtimeKernel) {
        qInfo() << "[RTScheduler] PREEMPT_RT kernel detected (bonus: bounded worst-case latency)";
    } else {
        qInfo() << "[RTScheduler] Standard preemptible kernel (CONFIG_PREEMPT). "
                   "PREEMPT_RT is not required for typical phone workloads.";
    }

    // Read-only check: musl's sched_setscheduler() is an ENOSYS stub, and
    // main() has already put this thread on SCHED_RR.
    int         policy = SCHED_OTHER;
    sched_param current{};
    pthread_getschedparam(pthread_self(), &policy, &current);
    struct rlimit rtprio{};
    const bool    rlimitAllows     = getrlimit(RLIMIT_RTPRIO, &rtprio) == 0 && rtprio.rlim_cur > 0;
    const bool    hasRTPermissions = policy == SCHED_RR || policy == SCHED_FIFO || rlimitAllows;
    if (hasRTPermissions) {
        qInfo() << "[RTScheduler] Real-time scheduling available";
    } else {
        qWarning() << "[RTScheduler] Real-time scheduling not permitted -- compositor and "
                      "input threads will run on SCHED_OTHER. Frame pacing may suffer "
                      "under heavy CPU load (background browsers, app launches, etc.).";
        qWarning() << "[RTScheduler] Fix: grant rtprio via /etc/security/limits.d/ "
                      "(file capabilities on the shell break its D-Bus session bus).";
    }
}

bool RTScheduler::isRealtimeKernel() const {
    return m_isRealtimeKernel;
}

QString RTScheduler::getCurrentPolicy() const {
    int policy = sched_getscheduler(0);

    switch (policy) {
        case SCHED_FIFO: return "SCHED_FIFO";
        case SCHED_RR: return "SCHED_RR";
        case SCHED_OTHER: return "SCHED_OTHER";
#ifdef SCHED_BATCH
        case SCHED_BATCH: return "SCHED_BATCH";
#endif
#ifdef SCHED_IDLE
        case SCHED_IDLE: return "SCHED_IDLE";
#endif
        default: return "UNKNOWN";
    }
}

int RTScheduler::getCurrentPriority() const {
    struct sched_param param;
    sched_getscheduler(0);

    if (sched_getparam(0, &param) == 0) {
        return param.sched_priority;
    }

    return -1;
}
