#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QTimer>

class QSocketNotifier;

// SIGTERMs pids, then SIGKILLs any still running after graceMs. Exits are
// watched through pidfds on the event loop, so the caller (the compositor)
// keeps serving clients meanwhile.
class ProcessStopper : public QObject {
    Q_OBJECT

  public:
    explicit ProcessStopper(QObject *parent = nullptr);
    ~ProcessStopper() override;

    void stop(const QList<qint64> &pids, int graceMs);

  signals:
    void finished(int killed);

  private:
    void                          exited(QSocketNotifier *notifier);
    void                          killRemaining();

    QHash<QSocketNotifier *, int> m_pidfds;
    QTimer                        m_deadline;
};
