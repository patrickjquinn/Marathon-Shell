#ifndef AUTOMATICTIMEZONE_H
#define AUTOMATICTIMEZONE_H

#include <QObject>
#include <QString>

class LocationManager;
class SettingsManager;

// Sets the system time zone from the location fix while automaticTimeZone
// is on. Never starts location itself: with the Location switch off there
// is no fix and the zone stays as it is.
class AutomaticTimeZone : public QObject {
    Q_OBJECT

  public:
    AutomaticTimeZone(SettingsManager *settings, LocationManager *location,
                      QObject *parent = nullptr);

    // The zone.tab zone whose principal city is nearest, or empty.
    static QString nearestZone(double latitude, double longitude,
                               const QString &zoneTab = QStringLiteral(
                                   "/usr/share/zoneinfo/zone.tab"));

  private:
    void             apply();

    SettingsManager *m_settings;
    LocationManager *m_location;
    bool             m_haveFix = false;
};

#endif
