#ifndef RATELIMITER_H
#define RATELIMITER_H

#include <QHash>
#include <QString>
#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>

class RateLimiter {
  public:
    bool tryAcquire(const QString &callerId, const QString &method, int maxCalls = 10,
                    int windowMs = 1000) {
        QMutexLocker locker(&m_mutex);

        QString      key = callerId + "::" + method;
        qint64       now = QDateTime::currentMSecsSinceEpoch();

        CallRecord  &record = m_records[key];

        while (!record.timestamps.isEmpty() && (now - record.timestamps.first()) > windowMs) {
            record.timestamps.removeFirst();
        }

        if (record.timestamps.size() >= maxCalls) {
            record.blocked = true;
            return false;
        }

        record.timestamps.append(now);
        record.blocked = false;
        return true;
    }

    double getRate(const QString &callerId, const QString &method) const {
        QMutexLocker locker(&m_mutex);

        QString      key = callerId + "::" + method;
        if (!m_records.contains(key)) {
            return 0.0;
        }

        const CallRecord &record = m_records[key];
        if (record.timestamps.size() < 2) {
            return 0.0;
        }

        qint64 now    = QDateTime::currentMSecsSinceEpoch();
        qint64 oldest = record.timestamps.first();
        qint64 span   = now - oldest;

        if (span <= 0) {
            return 0.0;
        }

        return (double)record.timestamps.size() / (span / 1000.0);
    }

    void clear() {
        QMutexLocker locker(&m_mutex);
        m_records.clear();
    }

    void clearCaller(const QString &callerId) {
        QMutexLocker locker(&m_mutex);
        QStringList  toRemove;
        for (auto it = m_records.begin(); it != m_records.end(); ++it) {
            if (it.key().startsWith(callerId + "::")) {
                toRemove.append(it.key());
            }
        }
        for (const QString &key : toRemove) {
            m_records.remove(key);
        }
    }

  private:
    struct CallRecord {
        QList<qint64> timestamps;
        bool          blocked = false;
    };

    mutable QMutex             m_mutex;
    QHash<QString, CallRecord> m_records;
};

#endif
