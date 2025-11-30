#pragma once

#include <QObject>
#include <QThread>

/**
 * @brief Real-Time Thread Scheduler for Marathon Shell
 * 
 * Implements SCHED_FIFO priority scheduling per Marathon OS Technical Spec:
 * - Priority 75: Compositor rendering thread
 * - Priority 85: Input event handling thread
 * 
 * Requires PREEMPT_RT kernel (Linux 6.12+) and CAP_SYS_NICE capability or
 * /etc/security/limits.d/99-marathon.conf configuration.
 */
class RTScheduler : public QObject {
    Q_OBJECT

  public:
    enum Priority {
        InputHandling    = 85, // Highest - instant touch response
        CompositorRender = 75, // High - smooth UI
        DefaultUserRT    = 80, // Default for user RT apps
        KernelIRQ        = 50  // Kernel IRQ handlers
    };

    explicit RTScheduler(QObject *parent = nullptr);

    /**
     * @brief Sets real-time priority for the calling thread
     * @param priority RT priority (1-99)
     * @return true if successful, false otherwise
     */
    Q_INVOKABLE bool setRealtimePriority(int priority);

    /**
     * @brief Sets real-time priority for a specific thread
     * @param thread QThread to set priority for
     * @param priority RT priority (1-99)
     * @return true if successful, false otherwise
     */
    Q_INVOKABLE bool setThreadPriority(QThread *thread, int priority);

    /**
     * @brief Checks if PREEMPT_RT kernel is active
     * @return true if running on PREEMPT_RT kernel
     */
    Q_INVOKABLE bool isRealtimeKernel() const;

    /**
     * @brief Checks if process has RT scheduling permissions
     * @return true if CAP_SYS_NICE or rtprio limit is set
     */
    Q_INVOKABLE bool hasRealtimePermissions() const;

    /**
     * @brief Gets current thread's scheduling policy
     * @return "SCHED_FIFO", "SCHED_RR", "SCHED_OTHER", etc.
     */
    Q_INVOKABLE QString getCurrentPolicy() const;

    /**
     * @brief Gets current thread's RT priority
     * @return Priority (0 for SCHED_OTHER, 1-99 for RT)
     */
    Q_INVOKABLE int getCurrentPriority() const;

  private:
    bool m_isRealtimeKernel;
    bool m_hasRTPermissions;

    void detectKernelCapabilities();
    bool setThreadSchedParam(int policy, int priority);
};
