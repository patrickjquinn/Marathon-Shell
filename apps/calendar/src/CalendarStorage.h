#pragma once

#include <QPointer>
#include <QDateTime>
#include <QVariantList>
#include <QObject>
#include <qqml.h>

class CalendarStorage : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantList events READ events NOTIFY eventsChanged)
    Q_PROPERTY(int nextEventId READ nextEventId NOTIFY nextEventIdChanged)

  public:
    explicit CalendarStorage(QObject *parent = nullptr);

    QVariantList events() const {
        return m_events;
    }
    int nextEventId() const {
        return m_nextEventId;
    }

    Q_INVOKABLE void         init();
    Q_INVOKABLE void         save();
    Q_INVOKABLE QVariantMap  addEvent(const QVariantMap &event);
    Q_INVOKABLE bool         updateEvent(const QVariantMap &event);
    Q_INVOKABLE bool         deleteEvent(int id);
    Q_INVOKABLE QVariantList getEventsForDate(const QDateTime &date);
    Q_INVOKABLE QVariantList getAllEvents() const;

  signals:
    void dataChanged();
    void eventsChanged();
    void nextEventIdChanged();

  private slots:
    void refreshFromManager();

  private:
    void              resolveCalendarManager();
    bool              hasManager() const;

    QPointer<QObject> m_calendarManager;
    QVariantList      m_events;
    int               m_nextEventId = 1;
};
