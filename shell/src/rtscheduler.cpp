#include "rtscheduler.h"
#include <QDebug>
#include <QFile>
#include <QTextStream>

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/capability.h>
#include <errno.h>
#endif

RTScheduler::RTScheduler(QObject *parent)
    : QObject(parent)
    , m_isRealtimeKernel(false)
    , m_hasRTPermissions(false)
{
    detectKernelCapabilities();
}

void RTScheduler::detectKernelCapabilities()
{
#ifdef Q_OS_LINUX
    // Check if running on PREEMPT_RT kernel
    QFile realtimeFile("/sys/kernel/realtime");
    if (realtimeFile.exists() && realtimeFile.open(QIODevice::ReadOnly)) {
        QTextStream stream(&realtimeFile);
        QString value = stream.readLine().trimmed();
        m_isRealtimeKernel = (value == "1");
        realtimeFile.close();
        
        if (m_isRealtimeKernel) {
            qInfo() << "[RTScheduler] ✓ PREEMPT_RT kernel detected";
        } else {
            qInfo() << "[RTScheduler] ⚠ Not running on PREEMPT_RT kernel";
        }
    } else {
        // Fallback: check uname for "PREEMPT_RT"
        QFile versionFile("/proc/version");
        if (versionFile.open(QIODevice::ReadOnly)) {
            QTextStream stream(&versionFile);
            QString version = stream.readAll();
            m_isRealtimeKernel = version.contains("PREEMPT_RT");
            versionFile.close();
        }
    }
    
    // Check if we have RT scheduling permissions
    struct sched_param param;
    param.sched_priority = 1;
    
    if (sched_setscheduler(0, SCHED_FIFO, &param) == 0) {
        m_hasRTPermissions = true;
        // Reset to normal scheduling
        param.sched_priority = 0;
        sched_setscheduler(0, SCHED_OTHER, &param);
        qInfo() << "[RTScheduler] ✓ RT scheduling permissions available";
    } else {
        m_hasRTPermissions = false;
        qWarning() << "[RTScheduler] ⚠ No RT scheduling permissions (CAP_SYS_NICE or limits.conf required)";
        qWarning() << "[RTScheduler]   Error:" << strerror(errno);
    }
#else
    qInfo() << "[RTScheduler] Not on Linux, RT scheduling disabled";
#endif
}

bool RTScheduler::setRealtimePriority(int priority)
{
#ifdef Q_OS_LINUX
    if (!m_hasRTPermissions) {
        qWarning() << "[RTScheduler] Cannot set RT priority without permissions";
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
    
    qInfo() << "[RTScheduler] ✓ Set thread RT priority:" << priority;
    return true;
#else
    Q_UNUSED(priority);
    return false;
#endif
}

bool RTScheduler::setThreadPriority(QThread *thread, int priority)
{
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
    
    // Get pthread handle from QThread
    pthread_t threadHandle = reinterpret_cast<pthread_t>(thread->currentThreadId());
    
    struct sched_param param;
    param.sched_priority = priority;
    
    if (pthread_setschedparam(threadHandle, SCHED_FIFO, &param) != 0) {
        qWarning() << "[RTScheduler] Failed to set thread RT priority:" << strerror(errno);
        return false;
    }
    
    qInfo() << "[RTScheduler] ✓ Set thread RT priority:" << priority;
    return true;
#else
    Q_UNUSED(thread);
    Q_UNUSED(priority);
    return false;
#endif
}

bool RTScheduler::isRealtimeKernel() const
{
    return m_isRealtimeKernel;
}

bool RTScheduler::hasRealtimePermissions() const
{
    return m_hasRTPermissions;
}

QString RTScheduler::getCurrentPolicy() const
{
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

int RTScheduler::getCurrentPriority() const
{
#ifdef Q_OS_LINUX
    struct sched_param param;
    int policy = sched_getscheduler(0);
    
    if (sched_getparam(0, &param) == 0) {
        return param.sched_priority;
    }
    
    return -1;
#else
    return 0;
#endif
}

