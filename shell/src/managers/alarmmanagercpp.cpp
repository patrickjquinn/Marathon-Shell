#include "alarmmanagercpp.h"
#include "settingsmanager.h"
#include "powermanagercpp.h"
#include "audiomanagercpp.h"
#include "hapticmanager.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QCryptographicHash>
#include <QSoundEffect>
#include <QUrl>
#include <QDebug>

Alarm Alarm::fromJson(const QJsonObject &json) {
    Alarm a;
    a.id             = json["id"].toString();
    a.time           = json["time"].toString();
    a.enabled        = json["enabled"].toBool();
    a.label          = json["label"].toString();
    a.sound          = json["sound"].toString();
    a.vibrate        = json["vibrate"].toBool();
    a.snoozeEnabled  = json["snoozeEnabled"].toBool();
    a.snoozeDuration = json["snoozeDuration"].toInt(10);

    QJsonArray repeatArr = json["repeat"].toArray();
    for (const auto &v : repeatArr) {
        a.repeat.append(v.toInt());
    }
    return a;
}

QJsonObject Alarm::toJson() const {
    QJsonObject json;
    json["id"]             = id;
    json["time"]           = time;
    json["enabled"]        = enabled;
    json["label"]          = label;
    json["sound"]          = sound;
    json["vibrate"]        = vibrate;
    json["snoozeEnabled"]  = snoozeEnabled;
    json["snoozeDuration"] = snoozeDuration;

    QJsonArray repeatArr;
    for (int day : repeat)
        repeatArr.append(day);
    json["repeat"] = repeatArr;

    return json;
}

QVariantMap Alarm::toVariantMap() const {
    return toJson().toVariantMap();
}

AlarmManagerCpp::AlarmManagerCpp(SettingsManager *settings, PowerManagerCpp *power,
                                 AudioManagerCpp *audio, HapticManager *haptic, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_power(power)
    , m_audio(audio)
    , m_haptic(haptic)
    , m_checkTimer(new QTimer(this))
    , m_soundEffect(new QSoundEffect(this)) {

    m_soundEffect->setLoopCount(QSoundEffect::Infinite);
    m_checkTimer->setSingleShot(true);
    connect(m_checkTimer, &QTimer::timeout, this, &AlarmManagerCpp::checkAlarms);

    QTimer::singleShot(0, this, [this]() {
        loadAlarms();
        scheduleNextAlarm();
    });
}

QVariantList AlarmManagerCpp::alarms() const {
    QVariantList list;
    for (const auto &a : m_alarms)
        list.append(a.toVariantMap());
    return list;
}

QVariantList AlarmManagerCpp::activeAlarms() const {
    QVariantList list;
    for (const auto &a : m_activeAlarms)
        list.append(a.toVariantMap());
    return list;
}

bool AlarmManagerCpp::hasEnabledAlarm() const {
    for (const auto &a : m_alarms) {
        if (a.enabled)
            return true;
    }
    return false;
}

bool AlarmManagerCpp::hasActiveAlarm() const {
    return !m_activeAlarms.isEmpty();
}

QString AlarmManagerCpp::createAlarm(const QString &time, const QString &label,
                                     const QList<int> &repeat, const QVariantMap &options) {
    Alarm a;
    a.time           = time;
    a.label          = label.isEmpty() ? "Alarm" : label;
    a.repeat         = repeat;
    a.enabled        = true;
    a.sound          = options.value("sound", "default").toString();
    a.vibrate        = options.value("vibrate", true).toBool();
    a.snoozeEnabled  = options.value("snoozeEnabled", true).toBool();
    a.snoozeDuration = options.value("snoozeDuration", 10).toInt();

    QString input = QString::number(QDateTime::currentMSecsSinceEpoch()) + time + label;
    a.id = QString(QCryptographicHash::hash(input.toUtf8(), QCryptographicHash::Md5).toHex());

    m_alarms.append(a);
    emit alarmsChanged();
    saveAlarms();
    scheduleNextAlarm();
    qInfo() << "[AlarmManagerCpp] Created alarm:" << a.id << "at" << time;
    return a.id;
}

bool AlarmManagerCpp::updateAlarm(const QString &id, const QVariantMap &updates) {
    for (auto &a : m_alarms) {
        if (a.id == id) {
            if (updates.contains("time"))
                a.time = updates["time"].toString();
            if (updates.contains("label"))
                a.label = updates["label"].toString();
            if (updates.contains("enabled"))
                a.enabled = updates["enabled"].toBool();
            if (updates.contains("sound"))
                a.sound = updates["sound"].toString();
            if (updates.contains("vibrate"))
                a.vibrate = updates["vibrate"].toBool();
            if (updates.contains("snoozeEnabled"))
                a.snoozeEnabled = updates["snoozeEnabled"].toBool();
            if (updates.contains("snoozeDuration"))
                a.snoozeDuration = updates["snoozeDuration"].toInt();
            if (updates.contains("repeat")) {
                a.repeat.clear();
                QVariantList r = updates["repeat"].toList();
                for (const auto &v : r)
                    a.repeat.append(v.toInt());
            }

            emit alarmsChanged();
            saveAlarms();
            scheduleNextAlarm();
            qInfo() << "[AlarmManagerCpp] Updated alarm:" << id;
            return true;
        }
    }
    return false;
}

bool AlarmManagerCpp::deleteAlarm(const QString &id) {
    for (int i = 0; i < m_alarms.size(); ++i) {
        if (m_alarms[i].id == id) {
            m_alarms.removeAt(i);
            emit alarmsChanged();
            saveAlarms();
            scheduleNextAlarm();
            qInfo() << "[AlarmManagerCpp] Deleted alarm:" << id;
            return true;
        }
    }
    return false;
}

bool AlarmManagerCpp::enableAlarm(const QString &id) {
    return updateAlarm(id, {{"enabled", true}});
}

bool AlarmManagerCpp::disableAlarm(const QString &id) {
    return updateAlarm(id, {{"enabled", false}});
}

bool AlarmManagerCpp::snoozeAlarm(const QString &id) {
    for (int i = 0; i < m_activeAlarms.size(); ++i) {
        if (m_activeAlarms[i].id == id) {
            Alarm a = m_activeAlarms[i];
            m_activeAlarms.removeAt(i);
            emit activeAlarmsChanged();

            if (m_activeAlarms.isEmpty())
                stopAll();

            qInfo() << "[AlarmManagerCpp] Snoozed alarm:" << id;
            emit alarmSnoozed(id, a.snoozeDuration);
            return true;
        }
    }
    return false;
}

bool AlarmManagerCpp::dismissAlarm(const QString &id) {
    for (int i = 0; i < m_activeAlarms.size(); ++i) {
        if (m_activeAlarms[i].id == id) {
            m_activeAlarms.removeAt(i);
            emit activeAlarmsChanged();

            if (m_activeAlarms.isEmpty())
                stopAll();

            emit alarmDismissed(id);
            qInfo() << "[AlarmManagerCpp] Dismissed alarm:" << id;
            scheduleNextAlarm();
            return true;
        }
    }
    return false;
}

void AlarmManagerCpp::stopAll() {
    if (m_soundEffect->isPlaying())
        m_soundEffect->stop();
    if (m_haptic)
        m_haptic->cancelVibration();
    if (m_power)
        m_power->releaseWakelock("alarm_ringing");
}

void AlarmManagerCpp::triggerAlarmNow(const QString &label) {
    Alarm a;
    a.time           = QTime::currentTime().toString("HH:mm");
    a.label          = label.isEmpty() ? "Test Alarm" : label;
    a.repeat         = {};
    a.enabled        = true;
    a.sound          = "default";
    a.vibrate        = true;
    a.snoozeEnabled  = true;
    a.snoozeDuration = 10;

    const QString input = QString::number(QDateTime::currentMSecsSinceEpoch()) + a.time + a.label;
    a.id = QString(QCryptographicHash::hash(input.toUtf8(), QCryptographicHash::Md5).toHex());
    triggerAlarm(a);
}

void AlarmManagerCpp::loadAlarms() {
    QString       jsonStr = m_settings->get("alarms/data", "[]").toString();
    QJsonDocument doc     = QJsonDocument::fromJson(jsonStr.toUtf8());
    QJsonArray    arr     = doc.array();

    m_alarms.clear();
    for (const auto &v : arr) {
        m_alarms.append(Alarm::fromJson(v.toObject()));
    }
    emit alarmsChanged();
    qInfo() << "[AlarmManagerCpp] Loaded" << m_alarms.size() << "alarms";
}

void AlarmManagerCpp::saveAlarms() {
    QJsonArray arr;
    for (const auto &a : m_alarms)
        arr.append(a.toJson());

    QJsonDocument doc(arr);
    m_settings->set("alarms/data", QString::fromUtf8(doc.toJson(QJsonDocument::Compact)));
}

void AlarmManagerCpp::scheduleNextAlarm() {
    QDateTime now = QDateTime::currentDateTime();
    QDateTime nextTime;
    bool      found = false;

    for (const auto &a : m_alarms) {
        if (!a.enabled)
            continue;
        QDateTime t = calculateNextOccurrence(a, now);
        if (!found || t < nextTime) {
            nextTime = t;
            found    = true;
        }
    }

    m_checkTimer->stop();
    if (found) {
        qint64 ms = now.msecsTo(nextTime);
        if (ms < 0)
            ms = 0;

        if (m_power)
            m_power->setRtcAlarm(nextTime.toSecsSinceEpoch());

        m_checkTimer->start(ms);
        qInfo() << "[AlarmManagerCpp] Next alarm in" << ms / 60000 << "minutes";
    }
}

QDateTime AlarmManagerCpp::calculateNextOccurrence(const Alarm &alarm, const QDateTime &from) {
    QStringList parts = alarm.time.split(":");
    if (parts.size() != 2)
        return from.addYears(1);

    int       h = parts[0].toInt();
    int       m = parts[1].toInt();

    QDateTime next = from;
    next.setTime(QTime(h, m));

    if (next <= from)
        next = next.addDays(1);

    if (alarm.repeat.isEmpty())
        return next;

    for (int i = 0; i < 7; ++i) {

        int checkDay = next.date().dayOfWeek() % 7;
        if (alarm.repeat.contains(checkDay))
            return next;

        next = next.addDays(1);
    }
    return next;
}

void AlarmManagerCpp::checkAlarms() {
    QDateTime now     = QDateTime::currentDateTime();
    QString   timeStr = now.time().toString("HH:mm");
    int       day     = now.date().dayOfWeek() % 7;

    for (const auto &a : m_alarms) {
        if (!a.enabled)
            continue;
        if (a.time != timeStr)
            continue;

        if (!a.repeat.isEmpty() && !a.repeat.contains(day))
            continue;

        triggerAlarm(a);
    }
    scheduleNextAlarm();
}

void AlarmManagerCpp::triggerAlarm(const Alarm &alarm) {
    qInfo() << "[AlarmManagerCpp] TRIGGERING ALARM:" << alarm.label;

    m_activeAlarms.append(alarm);
    emit activeAlarmsChanged();
    emit alarmTriggered(alarm.id, alarm.label);

    if (m_power)
        m_power->acquireWakelock("alarm_ringing");

    if (!alarm.sound.isEmpty()) {
        QString soundPath = alarm.sound;
        if (soundPath == "default" || soundPath.isEmpty()) {
            if (m_settings)
                soundPath = m_settings->alarmSound();
        }

        if (!soundPath.contains("://"))
            soundPath = "file://" + soundPath;

        m_soundEffect->setSource(QUrl(soundPath));
        m_soundEffect->setVolume(1.0);
        m_soundEffect->play();
    }

    if (m_haptic && alarm.vibrate) {
        QVariantList pattern;
        pattern << 500 << 500;
        m_haptic->vibratePatternVariant(pattern);
    }
}
