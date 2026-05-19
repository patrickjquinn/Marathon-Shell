#include "rtscheduler.h"
#include <QDebug>
#include <QFile>
#include <QTextStream>

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#endif

RTScheduler::RTScheduler(QObject *parent)
    : QObject(parent)
    , m_isRealtimeKernel(false)
    , m_hasRTPermissions(false) {
    detectKernelCapabilities();
}

void RTScheduler::detectKernelCapabilities() {
#ifdef Q_OS_LINUX
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

    // Probe RT-class permission -- the actual requirement.
    // Use SCHED_RR (the policy the compositor will adopt) so the probe
    // matches reality. CAP_SYS_NICE / rtprio in limits.conf governs both
    // SCHED_FIFO and SCHED_RR identically.
    struct sched_param param;
    param.sched_priority = 1;
    if (sched_setscheduler(0, SCHED_RR, &param) == 0) {
        m_hasRTPermissions   = true;
        param.sched_priority = 0;
        sched_setscheduler(0, SCHED_OTHER, &param);
        qInfo() << "[RTScheduler] Real-time scheduling available";
    } else {
        m_hasRTPermissions = false;
        const int err      = errno;
        qWarning() << "[RTScheduler] Real-time scheduling not permitted -- compositor and "
                      "input threads will run on SCHED_OTHER. Frame pacing may suffer "
                      "under heavy CPU load (background browsers, app launches, etc.).";
        qWarning() << "[RTScheduler] Fix: sudo setcap cap_sys_nice+ep "
                      "/usr/bin/marathon-shell-bin   (or grant rtprio via "
                      "/etc/security/limits.conf, then re-login).";
        if (err != EPERM && err != ENOSYS) {
            qWarning() << "[RTScheduler] System error:" << strerror(err);
        }
    }
#else
    qInfo() << "[RTScheduler] Not on Linux, RT scheduling disabled";
#endif
}

bool RTScheduler::setRealtimePriority(int priority) const {
#ifdef Q_OS_LINUX
    if (!m_hasRTPermissions) {
        qWarning() << "[RTScheduler] Cannot set RT priority - permissions not available (shell "
                      "running with degraded performance)";
        return false;
    }

    if (priority < 1 || priority > 99) {
        qWarning() << "[RTScheduler] Invalid priority:" << priority << "(must be 1-99)";
        return false;
    }

    struct sched_param param;
    param.sched_priority = priority;

    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) != 0) {
        qWarning() << "[RTScheduler] Failed to set RT priority:" << strerror(errno);
        return false;
    }

    qInfo() << "[RTScheduler] Set thread RT priority:" << priority;
    return true;
#else
    Q_UNUSED(priority);
    return false;
#endif
}

bool RTScheduler::setThreadPriority(QThread *thread, int priority) const {
#ifdef Q_OS_LINUX
    if (!thread) {
        qWarning() << "[RTScheduler] Null thread pointer";
        return false;
    }

    if (!m_hasRTPermissions) {
        qWarning() << "[RTScheduler] Cannot set RT priority without permissions";
        return false;
    }

    if (priority < 1 || priority > 99) {
        qWarning() << "[RTScheduler] Invalid priority:" << priority << "(must be 1-99)";
        return false;
    }

    pthread_t          threadHandle = reinterpret_cast<pthread_t>(QThread::currentThreadId());

    struct sched_param param;
    param.sched_priority = priority;

    if (pthread_setschedparam(threadHandle, SCHED_FIFO, &param) != 0) {
        qWarning() << "[RTScheduler] Failed to set thread RT priority:" << strerror(errno);
        return false;
    }

    qInfo() << "[RTScheduler] Set thread RT priority:" << priority;
    return true;
#else
    Q_UNUSED(thread);
    Q_UNUSED(priority);
    return false;
#endif
}

bool RTScheduler::isRealtimeKernel() const {
    return m_isRealtimeKernel;
}

bool RTScheduler::hasRealtimePermissions() const {
    return m_hasRTPermissions;
}

QString RTScheduler::getCurrentPolicy() const {
#ifdef Q_OS_LINUX
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
#else
    return "N/A (not Linux)";
#endif
}

int RTScheduler::getCurrentPriority() const {
#ifdef Q_OS_LINUX
    struct sched_param param;
    sched_getscheduler(0);

    if (sched_getparam(0, &param) == 0) {
        return param.sched_priority;
    }

    return -1;
#else
    return 0;
#endif
}
