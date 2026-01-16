#ifndef ALARMMANAGERCPP_H
#define ALARMMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QList>
#include <QVariantMap>
#include <QDateTime>
#include <QTimer>
#include <QJsonObject>

class SettingsManager;
class PowerManagerCpp;
class AudioManagerCpp;
class HapticManager;
class QSoundEffect;

struct Alarm {
    QString           id;
    QString           time;
    bool              enabled;
    QString           label;
    QList<int>        repeat;
    QString           sound;
    bool              vibrate;
    bool              snoozeEnabled;
    int               snoozeDuration;

    static Alarm      fromJson(const QJsonObject &json);
    QJsonObject       toJson() const;
    QVariantMap       toVariantMap() const;
    static QList<int> toIntList(const QJsonArray &array);
};

class AlarmManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList alarms READ alarms NOTIFY alarmsChanged)
    Q_PROPERTY(QVariantList activeAlarms READ activeAlarms NOTIFY activeAlarmsChanged)
    Q_PROPERTY(bool hasEnabledAlarm READ hasEnabledAlarm NOTIFY alarmsChanged)
    Q_PROPERTY(bool hasActiveAlarm READ hasActiveAlarm NOTIFY activeAlarmsChanged)

  public:
    explicit AlarmManagerCpp(SettingsManager *settings, PowerManagerCpp *power,
                             AudioManagerCpp *audio, HapticManager *haptic,
                             QObject *parent = nullptr);

    QVariantList        alarms() const;
    QVariantList        activeAlarms() const;
    bool                hasEnabledAlarm() const;
    bool                hasActiveAlarm() const;

    Q_INVOKABLE QString createAlarm(const QString &time, const QString &label,
                                    const QList<int> &repeat, const QVariantMap &options);
    Q_INVOKABLE bool    updateAlarm(const QString &id, const QVariantMap &updates);
    Q_INVOKABLE bool    deleteAlarm(const QString &id);
    Q_INVOKABLE bool    enableAlarm(const QString &id);
    Q_INVOKABLE bool    disableAlarm(const QString &id);
    Q_INVOKABLE bool    snoozeAlarm(const QString &id);
    Q_INVOKABLE bool    dismissAlarm(const QString &id);
    Q_INVOKABLE void    stopAll();
    Q_INVOKABLE void    triggerAlarmNow(const QString &label = QString());

  signals:
    void alarmsChanged();
    void activeAlarmsChanged();
    void alarmTriggered(const QString &id, const QString &label);
    void alarmDismissed(const QString &id);
    void alarmSnoozed(const QString &id, int minutes);

  private slots:
    void checkAlarms();

  private:
    void             loadAlarms();
    void             saveAlarms();
    void             scheduleNextAlarm();
    void             triggerAlarm(const Alarm &alarm);
    QDateTime        calculateNextOccurrence(const Alarm &alarm, const QDateTime &from);

    SettingsManager *m_settings;
    PowerManagerCpp *m_power;
    AudioManagerCpp *m_audio;
    HapticManager   *m_haptic;

    QList<Alarm>     m_alarms;
    QList<Alarm>     m_activeAlarms;
    QTimer          *m_checkTimer;
    QSoundEffect    *m_soundEffect;
};

#endif
