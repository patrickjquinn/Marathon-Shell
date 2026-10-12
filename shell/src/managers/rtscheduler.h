#pragma once

#include <QObject>

class RTScheduler : public QObject {
    Q_OBJECT

  public:
    explicit RTScheduler(QObject *parent = nullptr);

    Q_INVOKABLE bool    isRealtimeKernel() const;

    Q_INVOKABLE QString getCurrentPolicy() const;

    Q_INVOKABLE int     getCurrentPriority() const;

  private:
    bool m_isRealtimeKernel;

    void detectKernelCapabilities();
};
