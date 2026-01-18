#pragma once

#include <QObject>
#include <QThread>

class RTScheduler : public QObject {
    Q_OBJECT

  public:
    enum Priority {
        InputHandling    = 85,
        CompositorRender = 75,
        DefaultUserRT    = 80,
        KernelIRQ        = 50
    };

    explicit RTScheduler(QObject *parent = nullptr);

    Q_INVOKABLE bool    setRealtimePriority(int priority);

    Q_INVOKABLE bool    setThreadPriority(QThread *thread, int priority);

    Q_INVOKABLE bool    isRealtimeKernel() const;

    Q_INVOKABLE bool    hasRealtimePermissions() const;

    Q_INVOKABLE QString getCurrentPolicy() const;

    Q_INVOKABLE int     getCurrentPriority() const;

  private:
    bool m_isRealtimeKernel;
    bool m_hasRTPermissions;

    void detectKernelCapabilities();
    bool setThreadSchedParam(int policy, int priority);
};
