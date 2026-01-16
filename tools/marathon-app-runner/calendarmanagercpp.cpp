#include "calendarmanagercpp.h"
#include "ipc/shellipcclients.h"

#include <QDate>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

CalendarManagerCpp::CalendarManagerCpp(SettingsClient *settings, NotificationClient *notifications,
                                       QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_notifications(notifications) {
    load();
    updateNextEventId();
    emit eventsLoaded();

    m_checkTimer = new QTimer(this);
    m_checkTimer->setInterval(60 * 1000);
    connect(m_checkTimer, &QTimer::timeout, this, &CalendarManagerCpp::checkReminders);
    m_checkTimer->start();
    checkReminders();
}

QVariantMap CalendarManagerCpp::createEvent(const QVariantMap &event) {
    QVariantMap normalized  = normalizeEvent(event);
    normalized["id"]        = m_nextEventId++;
    normalized["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    m_events.append(normalized);
    save();
    emit eventsChanged();
    emit nextEventIdChanged();
    emit eventCreated(normalized);
    return normalized;
}

bool CalendarManagerCpp::updateEvent(const QVariantMap &event) {
    if (!event.contains("id"))
        return false;

    const int id = event.value("id").toInt();
    for (int i = 0; i < m_events.size(); ++i) {
        const QVariantMap existing = m_events[i].toMap();
        if (existing.value("id").toInt() == id) {
            QVariantMap normalized = normalizeEvent(event);
            normalized["id"]       = id;
            m_events[i]            = normalized;
            save();
            emit eventsChanged();
            emit eventUpdated(normalized);
            return true;
        }
    }
    return false;
}

bool CalendarManagerCpp::deleteEvent(int id) {
    for (int i = 0; i < m_events.size(); ++i) {
        const QVariantMap existing = m_events[i].toMap();
        if (existing.value("id").toInt() == id) {
            m_events.removeAt(i);
            save();
            emit eventsChanged();
            emit eventDeleted(id);
            return true;
        }
    }
    return false;
}

QVariantList CalendarManagerCpp::getEventsForDate(const QDateTime &date) const {
    const QString dateStr = date.date().toString("yyyy-MM-dd");
    QVariantList  result;
    for (const QVariant &entry : m_events) {
        const QVariantMap event        = entry.toMap();
        const QString     eventDateStr = event.value("date").toString();
        if (eventDateStr == dateStr) {
            result.append(event);
            continue;
        }

        const QString recurring = event.value("recurring", "none").toString();
        if (recurring == "none")
            continue;

        const QDate eventDate = QDate::fromString(eventDateStr, "yyyy-MM-dd");
        const QDate checkDate = date.date();
        if (!eventDate.isValid() || checkDate < eventDate)
            continue;

        if (recurring == "daily") {
            result.append(event);
        } else if (recurring == "weekly") {
            const int daysDiff = eventDate.daysTo(checkDate);
            if (daysDiff % 7 == 0)
                result.append(event);
        } else if (recurring == "monthly") {
            if (eventDate.day() == checkDate.day())
                result.append(event);
        }
    }
    return result;
}

QVariantList CalendarManagerCpp::getAllEvents() const {
    return m_events;
}

void CalendarManagerCpp::checkReminders() {
    const QDateTime now = QDateTime::currentDateTime();
    for (const QVariant &entry : m_events) {
        const QVariantMap event = entry.toMap();
        if (!shouldTriggerEvent(event, now))
            continue;

        const QString key = triggerKeyForEvent(event, now);
        if (m_triggered.contains(key))
            continue;

        triggerNotification(event);
        m_triggered.append(key);
        if (m_triggered.size() > 50)
            m_triggered.removeFirst();
    }
}

void CalendarManagerCpp::load() {
    if (!m_settings) {
        m_events.clear();
        return;
    }

    const QVariant raw = m_settings->get("calendar/events", QVariantList());
    if (raw.canConvert<QVariantList>()) {
        m_events = raw.toList();
        return;
    }

    if (raw.typeId() == QMetaType::QString) {
        const QJsonDocument doc = QJsonDocument::fromJson(raw.toString().toUtf8());
        if (!doc.isArray()) {
            m_events.clear();
            return;
        }
        const QJsonArray arr = doc.array();
        m_events.clear();
        m_events.reserve(arr.size());
        for (const QJsonValue &value : arr) {
            if (value.isObject())
                m_events.append(value.toObject().toVariantMap());
        }
        return;
    }

    m_events.clear();
}

void CalendarManagerCpp::save() {
    if (!m_settings)
        return;
    m_settings->set("calendar/events", m_events);
}

void CalendarManagerCpp::updateNextEventId() {
    int maxId = 0;
    for (const QVariant &entry : m_events) {
        const QVariantMap event = entry.toMap();
        maxId                   = std::max(maxId, event.value("id").toInt());
    }
    if (maxId + 1 != m_nextEventId) {
        m_nextEventId = maxId + 1;
        emit nextEventIdChanged();
    }
}

QVariantMap CalendarManagerCpp::normalizeEvent(const QVariantMap &event) const {
    QVariantMap normalized = event;
    if (!normalized.contains("title"))
        normalized["title"] = "";
    if (!normalized.contains("date"))
        normalized["date"] = "";
    if (!normalized.contains("time"))
        normalized["time"] = "";
    if (!normalized.contains("allDay"))
        normalized["allDay"] = false;
    if (!normalized.contains("recurring"))
        normalized["recurring"] = "none";
    if (!normalized.contains("description"))
        normalized["description"] = "";
    return normalized;
}

bool CalendarManagerCpp::shouldTriggerEvent(const QVariantMap &event, const QDateTime &now) const {
    const QString dateStr   = now.date().toString("yyyy-MM-dd");
    const QString timeStr   = now.time().toString("HH:mm");
    const QString eventDate = event.value("date").toString();
    const QString eventTime = event.value("time").toString();
    if (eventTime != timeStr)
        return false;

    const QString recurring = event.value("recurring", "none").toString();
    if (eventDate == dateStr)
        return true;

    if (recurring == "none")
        return false;

    const QDate baseDate = QDate::fromString(eventDate, "yyyy-MM-dd");
    if (!baseDate.isValid() || now.date() < baseDate)
        return false;

    if (recurring == "daily")
        return true;
    if (recurring == "weekly") {
        const int daysDiff = baseDate.daysTo(now.date());
        return daysDiff % 7 == 0;
    }
    if (recurring == "monthly")
        return baseDate.day() == now.date().day();

    return false;
}

void CalendarManagerCpp::triggerNotification(const QVariantMap &event) {
    if (!m_notifications)
        return;

    const QString title  = event.value("title").toString();
    const QString time   = event.value("time").toString();
    const bool    allDay = event.value("allDay").toBool();
    const QString body   = allDay ? QStringLiteral("%1 (All Day)").arg(time) : time;

    QVariantMap   options;
    options.insert("icon", "qrc:/images/calendar.svg");
    options.insert("category", "reminder");
    options.insert("priority", "high");
    options.insert("actions", QVariantList{"Dismiss"});

    m_notifications->sendNotification("calendar", title, body, options);
}

QString CalendarManagerCpp::triggerKeyForEvent(const QVariantMap &event,
                                               const QDateTime   &now) const {
    return QString("%1_%2_%3")
        .arg(event.value("id").toInt())
        .arg(now.date().toString("yyyy-MM-dd"))
        .arg(now.time().toString("HH:mm"));
}
