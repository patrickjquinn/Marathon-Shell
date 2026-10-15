#include "processstopper.h"

#include <QSocketNotifier>

#include <csignal>
#include <sys/syscall.h>
#include <unistd.h>

static int pidfdOpen(qint64 pid) {
    return static_cast<int>(::syscall(SYS_pidfd_open, static_cast<pid_t>(pid), 0));
}

static bool pidfdSignal(int pidfd, int sig) {
    return ::syscall(SYS_pidfd_send_signal, pidfd, sig, nullptr, 0) == 0;
}

ProcessStopper::ProcessStopper(QObject *parent)
    : QObject(parent) {
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, &ProcessStopper::killRemaining);
}

ProcessStopper::~ProcessStopper() {
    for (auto it = m_pidfds.cbegin(); it != m_pidfds.cend(); ++it)
        ::close(it.value());
}

void ProcessStopper::stop(const QList<qint64> &pids, int graceMs) {
    for (const qint64 pid : pids) {
        const int pidfd = pid > 0 ? pidfdOpen(pid) : -1;
        if (pidfd < 0)
            continue;
        if (!pidfdSignal(pidfd, SIGTERM)) {
            ::close(pidfd);
            continue;
        }
        // A pidfd polls readable once its process has exited, reaped or not.
        auto *notifier = new QSocketNotifier(pidfd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this,
                [this, notifier]() { exited(notifier); });
        m_pidfds.insert(notifier, pidfd);
    }
    if (m_pidfds.isEmpty()) {
        emit finished(0);
        return;
    }
    m_deadline.start(graceMs);
}

void ProcessStopper::exited(QSocketNotifier *notifier) {
    notifier->setEnabled(false);
    notifier->deleteLater();
    ::close(m_pidfds.take(notifier));
    if (!m_pidfds.isEmpty())
        return;
    m_deadline.stop();
    emit finished(0);
}

void ProcessStopper::killRemaining() {
    int killed = 0;
    for (auto it = m_pidfds.cbegin(); it != m_pidfds.cend(); ++it) {
        if (pidfdSignal(it.value(), SIGKILL))
            ++killed;
        it.key()->setEnabled(false);
        it.key()->deleteLater();
        ::close(it.value());
    }
    m_pidfds.clear();
    emit finished(killed);
}
