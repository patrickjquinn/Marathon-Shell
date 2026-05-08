#include "davcalendarstore.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>

DavCalendarStore::DavCalendarStore(QObject *parent)
    : QObject(parent) {
    initDb();
}

void DavCalendarStore::initDb() {
    const QString dataDir =
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/marathon";
    QDir().mkpath(dataDir);
    const QString dbPath = dataDir + "/dav-events.db";

    m_db = QSqlDatabase::addDatabase("QSQLITE", "DavCalendarStore");
    m_db.setDatabaseName(dbPath);
    if (!m_db.open()) {
        qWarning() << "[DavCalendarStore] open failed:" << m_db.lastError().text() << "@" << dbPath;
        return;
    }
    QSqlQuery q(m_db);
    if (!q.exec("CREATE TABLE IF NOT EXISTS events ("
                "uid TEXT PRIMARY KEY,"
                "account_id TEXT,"
                "summary TEXT,"
                "description TEXT,"
                "start_ms INTEGER,"
                "end_ms INTEGER,"
                "all_day INTEGER DEFAULT 0,"
                "location TEXT,"
                "updated_at INTEGER)")) {
        qWarning() << "[DavCalendarStore] schema create failed:" << q.lastError().text();
    }
    q.exec("CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_ms)");
}

void DavCalendarStore::upsertEvent(const QString &uid, const QString &summary,
                                   const QString &description, qint64 startMs, qint64 endMs,
                                   bool allDay, const QString &location, const QString &accountId) {
    if (uid.isEmpty() || !m_db.isOpen())
        return;
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO events(uid, account_id, summary, description, start_ms, end_ms,"
              "                   all_day, location, updated_at) "
              "VALUES (:uid, :acct, :sum, :desc, :sms, :ems, :ad, :loc, :upd) "
              "ON CONFLICT(uid) DO UPDATE SET "
              "  account_id=:acct, summary=:sum, description=:desc, "
              "  start_ms=:sms, end_ms=:ems, all_day=:ad, location=:loc, updated_at=:upd");
    q.bindValue(":uid", uid);
    q.bindValue(":acct", accountId);
    q.bindValue(":sum", summary);
    q.bindValue(":desc", description);
    q.bindValue(":sms", startMs);
    q.bindValue(":ems", endMs);
    q.bindValue(":ad", allDay ? 1 : 0);
    q.bindValue(":loc", location);
    q.bindValue(":upd", QDateTime::currentMSecsSinceEpoch());
    if (!q.exec()) {
        qWarning() << "[DavCalendarStore] upsert failed:" << q.lastError().text();
        return;
    }
    emit eventsChanged();
}

void DavCalendarStore::removeEvent(const QString &uid) {
    if (uid.isEmpty() || !m_db.isOpen())
        return;
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM events WHERE uid = :uid");
    q.bindValue(":uid", uid);
    if (q.exec())
        emit eventsChanged();
}

QVariantList DavCalendarStore::eventsInRange(qint64 startMs, qint64 endMs) const {
    QVariantList out;
    if (!m_db.isOpen())
        return out;
    QSqlQuery q(m_db);
    q.prepare("SELECT uid, account_id, summary, description, start_ms, end_ms, "
              "       all_day, location FROM events "
              "WHERE end_ms >= :s AND start_ms <= :e ORDER BY start_ms ASC");
    q.bindValue(":s", startMs);
    q.bindValue(":e", endMs);
    if (!q.exec())
        return out;
    while (q.next()) {
        QVariantMap m;
        m["uid"]         = q.value(0).toString();
        m["accountId"]   = q.value(1).toString();
        m["summary"]     = q.value(2).toString();
        m["description"] = q.value(3).toString();
        m["startMs"]     = q.value(4).toLongLong();
        m["endMs"]       = q.value(5).toLongLong();
        m["allDay"]      = q.value(6).toInt() == 1;
        m["location"]    = q.value(7).toString();
        out.append(m);
    }
    return out;
}

QVariantList DavCalendarStore::allEvents() const {
    return eventsInRange(0, std::numeric_limits<qint64>::max());
}
