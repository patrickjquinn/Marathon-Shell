#include "CalendarStorage.h"

#include <QMetaMethod>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>

CalendarStorage::CalendarStorage(QObject *parent)
    : QObject(parent) {
    QTimer::singleShot(0, this, &CalendarStorage::resolveCalendarManager);
}

void CalendarStorage::init() {
    if (!hasManager()) {
        return;
    }
    refreshFromManager();
    emit dataChanged();
}

void CalendarStorage::save() {
    emit dataChanged();
}

QVariantMap CalendarStorage::addEvent(const QVariantMap &event) {
    if (!hasManager()) {
        return {};
    }
    QVariantMap result;
    QMetaObject::invokeMethod(m_calendarManager, "createEvent", Q_RETURN_ARG(QVariantMap, result),
                              Q_ARG(QVariantMap, event));
    refreshFromManager();
    emit dataChanged();
    return result;
}

bool CalendarStorage::updateEvent(const QVariantMap &event) {
    if (!hasManager()) {
        return false;
    }
    bool result = false;
    QMetaObject::invokeMethod(m_calendarManager, "updateEvent", Q_RETURN_ARG(bool, result),
                              Q_ARG(QVariantMap, event));
    refreshFromManager();
    emit dataChanged();
    return result;
}

bool CalendarStorage::deleteEvent(int id) {
    if (!hasManager()) {
        return false;
    }
    bool result = false;
    QMetaObject::invokeMethod(m_calendarManager, "deleteEvent", Q_RETURN_ARG(bool, result),
                              Q_ARG(int, id));
    refreshFromManager();
    emit dataChanged();
    return result;
}

QVariantList CalendarStorage::getEventsForDate(const QDateTime &date) {
    if (!hasManager()) {
        return {};
    }
    QVariantList result;
    QMetaObject::invokeMethod(m_calendarManager, "getEventsForDate",
                              Q_RETURN_ARG(QVariantList, result), Q_ARG(QDateTime, date));
    return result;
}

QVariantList CalendarStorage::getAllEvents() const {
    return m_events;
}

void CalendarStorage::refreshFromManager() {
    if (!hasManager()) {
        return;
    }
    const QVariant eventsValue = m_calendarManager->property("events");
    if (eventsValue.isValid()) {
        const QVariantList updated = eventsValue.toList();
        if (m_events != updated) {
            m_events = updated;
            emit eventsChanged();
        }
    }
    const QVariant nextIdValue = m_calendarManager->property("nextEventId");
    if (nextIdValue.isValid()) {
        const int nextId = nextIdValue.toInt();
        if (m_nextEventId != nextId) {
            m_nextEventId = nextId;
            emit nextEventIdChanged();
        }
    }
}

void CalendarStorage::resolveCalendarManager() {
    if (m_calendarManager) {
        return;
    }
    QQmlEngine *engine = qmlEngine(this);
    if (!engine) {
        return;
    }
    QObject *manager = engine->rootContext()->contextProperty("CalendarManager").value<QObject *>();
    if (!manager) {
        return;
    }
    m_calendarManager            = manager;
    const QMetaObject *meta      = m_calendarManager->metaObject();
    const int          slotIndex = metaObject()->indexOfSlot("refreshFromManager()");
    const int          loaded    = meta->indexOfSignal("eventsLoaded()");
    if (loaded != -1) {
        QMetaObject::connect(m_calendarManager, loaded, this, slotIndex);
    }
    const int created = meta->indexOfSignal("eventCreated(QVariantMap)");
    if (created != -1) {
        QMetaObject::connect(m_calendarManager, created, this, slotIndex);
    }
    const int updated = meta->indexOfSignal("eventUpdated(QVariantMap)");
    if (updated != -1) {
        QMetaObject::connect(m_calendarManager, updated, this, slotIndex);
    }
    const int deleted = meta->indexOfSignal("eventDeleted(int)");
    if (deleted != -1) {
        QMetaObject::connect(m_calendarManager, deleted, this, slotIndex);
    }
    refreshFromManager();
}

bool CalendarStorage::hasManager() const {
    return m_calendarManager;
}
