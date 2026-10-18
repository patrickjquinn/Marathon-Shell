#include "TimeZoneList.h"

#include <QDateTime>
#include <QFile>
#include <QSet>
#include <QTimeZone>
#include <algorithm>

namespace {
    QString offsetLabel(int seconds) {
        if (seconds == 0)
            return QStringLiteral("GMT");
        const int minutes = std::abs(seconds) / 60;
        QString   label =
            QStringLiteral("GMT%1%2").arg(seconds < 0 ? '-' : '+').arg(minutes / 60);
        if (minutes % 60)
            label += QStringLiteral(":%1").arg(minutes % 60, 2, 10, QLatin1Char('0'));
        return label;
    }

    // Canonical zones only: availableTimeZoneIds() also lists backward links like Australia/ACT.
    QSet<QString> canonicalZones() {
        QSet<QString> ids;
        QFile         tab(QStringLiteral("/usr/share/zoneinfo/zone.tab"));
        if (!tab.open(QIODevice::ReadOnly | QIODevice::Text))
            return ids;
        while (!tab.atEnd()) {
            const QByteArray line = tab.readLine();
            if (line.startsWith('#'))
                continue;
            const QList<QByteArray> fields = line.trimmed().split('\t');
            if (fields.size() >= 3)
                ids.insert(QString::fromUtf8(fields.at(2)));
        }
        return ids;
    }
}

TimeZoneList::TimeZoneList(QObject *parent)
    : QObject(parent) {
    static const QStringList regions{"Africa",   "America", "Antarctica", "Asia",   "Atlantic",
                                     "Australia", "Europe",  "Indian",     "Pacific"};
    const QDateTime          now = QDateTime::currentDateTimeUtc();
    QList<QVariantMap>       zones;
    const QSet<QString>      canonical = canonicalZones();
    const QList<QByteArray> rawIds = QTimeZone::availableTimeZoneIds();
    for (const QByteArray &rawId : rawIds) {
        const QString id     = QString::fromUtf8(rawId);
        const QString region = id.section('/', 0, 0);
        if (!regions.contains(region) || !id.contains('/') ||
            (!canonical.isEmpty() && !canonical.contains(id)))
            continue;
        const QTimeZone tz(rawId);
        zones.append({{"id", id},
                      {"city", id.section('/', -1).replace('_', ' ')},
                      {"region", region},
                      {"offset", offsetLabel(tz.offsetFromUtc(now))}});
    }
    std::sort(zones.begin(), zones.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value("city").toString().localeAwareCompare(b.value("city").toString()) < 0;
    });
    for (const QVariantMap &z : zones)
        m_zones.append(z);
}

QVariantList TimeZoneList::search(const QString &query) const {
    const QString q = query.trimmed();
    if (q.isEmpty())
        return m_zones;
    QVariantList out;
    for (const QVariant &v : m_zones) {
        const QVariantMap z = v.toMap();
        if (z.value("city").toString().contains(q, Qt::CaseInsensitive) ||
            z.value("region").toString().contains(q, Qt::CaseInsensitive) ||
            z.value("id").toString().contains(q, Qt::CaseInsensitive))
            out.append(z);
    }
    return out;
}

QString TimeZoneList::displayName(const QString &zoneId) const {
    const QTimeZone tz(zoneId.toUtf8());
    if (!tz.isValid())
        return zoneId;
    const QString city = zoneId.contains('/') ? zoneId.section('/', -1).replace('_', ' ') : zoneId;
    return city + QStringLiteral(" (") + offsetLabel(tz.offsetFromUtc(QDateTime::currentDateTimeUtc())) +
        QStringLiteral(")");
}
