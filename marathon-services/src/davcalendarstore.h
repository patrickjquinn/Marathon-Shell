#ifndef DAVCALENDARSTORE_H
#define DAVCALENDARSTORE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>

// Shell-side store for events ingested via CardDAV/CalDAV. The on-device
// calendar app reads this store in addition to its own per-app storage.
//
// Schema: a single `events` table keyed by uid (vCalendar UID). Last-write-
// wins on conflict (matches DavSyncEngine's overall sync model).
class DavCalendarStore : public QObject {
    Q_OBJECT

  public:
    explicit DavCalendarStore(QObject *parent = nullptr);

    // Idempotent on UID. summary/description are plain text. start/end are
    // ms-since-epoch UTC. allDay flagged when DTSTART has VALUE=DATE.
    Q_INVOKABLE void         upsertEvent(const QString &uid, const QString &summary,
                                         const QString &description, qint64 startMs, qint64 endMs,
                                         bool allDay, const QString &location, const QString &accountId);

    Q_INVOKABLE void         removeEvent(const QString &uid);

    Q_INVOKABLE QVariantList eventsInRange(qint64 startMs, qint64 endMs) const;

    Q_INVOKABLE QVariantList allEvents() const;

  signals:
    void eventsChanged();

  private:
    void         initDb();
    QSqlDatabase m_db;
};

#endif
