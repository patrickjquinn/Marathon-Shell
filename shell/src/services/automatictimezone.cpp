#include "automatictimezone.h"

#include "src/managers/locationmanager.h"
#include "src/managers/settingsmanager.h"

#include <QDebug>
#include <QFile>
#include <QRegularExpression>
#include <algorithm>
#include <cmath>

namespace {
    // ISO 6709 +DDMM[SS] / +DDDMM[SS] as degrees.
    double iso6709(const QString &s, int degreeDigits) {
        const double sign = s.startsWith(QLatin1Char('-')) ? -1.0 : 1.0;
        const QString d   = s.mid(1);
        double        v   = d.left(degreeDigits).toDouble() + d.mid(degreeDigits, 2).toDouble() / 60.0;
        if (d.size() > degreeDigits + 2)
            v += d.mid(degreeDigits + 2, 2).toDouble() / 3600.0;
        return sign * v;
    }

    double radians(double degrees) {
        return degrees * M_PI / 180.0;
    }
}

AutomaticTimeZone::AutomaticTimeZone(SettingsManager *settings, LocationManager *location,
                                     QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_location(location) {
    connect(m_location, &LocationManager::locationChanged, this, [this]() {
        m_haveFix = true;
        apply();
    });
    connect(m_settings, &SettingsManager::automaticTimeZoneChanged, this,
            &AutomaticTimeZone::apply);
}

QString AutomaticTimeZone::nearestZone(double latitude, double longitude, const QString &zoneTab) {
    QFile tab(zoneTab);
    if (!tab.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    static const QRegularExpression coords(QStringLiteral("^([+-]\\d{4,6})([+-]\\d{5,7})$"));
    const double lat = radians(latitude);
    const double lon = radians(longitude);
    QString      best;
    double       bestAngle = 4.0;
    while (!tab.atEnd()) {
        const QString line = QString::fromUtf8(tab.readLine()).trimmed();
        if (line.startsWith(QLatin1Char('#')))
            continue;
        const QStringList fields = line.split(QLatin1Char('\t'));
        if (fields.size() < 3)
            continue;
        const QRegularExpressionMatch m = coords.match(fields.at(1));
        if (!m.hasMatch())
            continue;
        const double zLat = radians(iso6709(m.captured(1), 2));
        const double zLon = radians(iso6709(m.captured(2), 3));
        const double cosAngle = std::sin(lat) * std::sin(zLat)
                                + std::cos(lat) * std::cos(zLat) * std::cos(lon - zLon);
        const double angle = std::acos(std::clamp(cosAngle, -1.0, 1.0));
        if (angle < bestAngle) {
            bestAngle = angle;
            best      = fields.at(2);
        }
    }
    return best;
}

void AutomaticTimeZone::apply() {
    if (!m_settings->automaticTimeZone() || !m_haveFix || !m_location->active())
        return;
    const QString zone = nearestZone(m_location->latitude(), m_location->longitude());
    if (zone.isEmpty() || zone == m_settings->timeZone())
        return;
    qInfo() << "[AutomaticTimeZone]" << m_settings->timeZone() << "->" << zone;
    m_settings->setTimeZone(zone);
}
