#ifndef CALENDARMANAGERCPP_H
#define CALENDARMANAGERCPP_H

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class SettingsClient;
class NotificationClient;

class CalendarManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList events READ events NOTIFY eventsChanged)
    Q_PROPERTY(int nextEventId READ nextEventId NOTIFY nextEventIdChanged)

  public:
    explicit CalendarManagerCpp(SettingsClient *settings, NotificationClient *notifications,
                                QObject *parent = nullptr);

    QVariantList events() const {
        return m_events;
    }
    int nextEventId() const {
        return m_nextEventId;
    }

    Q_INVOKABLE QVariantMap  createEvent(const QVariantMap &event);
    Q_INVOKABLE bool         updateEvent(const QVariantMap &event);
    Q_INVOKABLE bool         deleteEvent(int id);
    Q_INVOKABLE QVariantList getEventsForDate(const QDateTime &date) const;
    Q_INVOKABLE QVariantList getAllEvents() const;

  signals:
    void eventsChanged();
    void nextEventIdChanged();
    void eventCreated(const QVariantMap &event);
    void eventUpdated(const QVariantMap &event);
    void eventDeleted(int eventId);
    void eventsLoaded();

  private slots:
    void checkReminders();

  private:
    void                load();
    void                save();
    void                updateNextEventId();
    QVariantMap         normalizeEvent(const QVariantMap &event) const;
    bool                shouldTriggerEvent(const QVariantMap &event, const QDateTime &now) const;
    void                triggerNotification(const QVariantMap &event);
    QString             triggerKeyForEvent(const QVariantMap &event, const QDateTime &now) const;

    SettingsClient     *m_settings      = nullptr;
    NotificationClient *m_notifications = nullptr;
    QVariantList        m_events;
    int                 m_nextEventId = 1;
    QTimer             *m_checkTimer  = nullptr;
    QStringList         m_triggered;
};

#endif
