#pragma once

#include <QDateTime>
#include <QObject>
#include <QTimeZone>
#include <QVariantMap>

// Tiny QObject helper that exposes QTimeZone to QML. Qt's QML JS engine
// silently ignores the `timeZone` option on Date.toLocaleString, so apps
// that need DST-correct wall-clock times across IANA zones can't use the
// pure-JS path. WorldClockHelper.timeIn("America/New_York") returns the
// formatted time/weekday/offset map.
class WorldClockHelper : public QObject {
    Q_OBJECT
  public:
    explicit WorldClockHelper(QObject *parent = nullptr)
        : QObject(parent) {}

    Q_INVOKABLE QVariantMap timeIn(const QString &tzId) const {
        QVariantMap out;
        QTimeZone   tz(tzId.toUtf8());
        if (!tz.isValid()) {
            out["time"]        = "—:—";
            out["weekday"]     = "";
            out["offsetLabel"] = tzId;
            return out;
        }
        const QDateTime now      = QDateTime::currentDateTime();
        const QDateTime targetTz = now.toTimeZone(tz);
        out["time"]              = targetTz.toString("h:mm AP");
        out["weekday"]           = targetTz.toString("ddd").toUpper();

        // Offset relative to local in hours (DST-aware via QTimeZone).
        const int targetOffset = tz.offsetFromUtc(now);
        const int localOffset  = QTimeZone::systemTimeZone().offsetFromUtc(now);
        const int diffHours    = (targetOffset - localOffset) / 3600;
        if (diffHours == 0)
            out["offsetLabel"] = "Local";
        else
            out["offsetLabel"] = QString("%1%2h").arg(diffHours > 0 ? "+" : "").arg(diffHours);
        return out;
    }
};
