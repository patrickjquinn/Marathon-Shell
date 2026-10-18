#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>

class TimeZoneList : public QObject {
    Q_OBJECT
    QML_ELEMENT

  public:
    explicit TimeZoneList(QObject *parent = nullptr);

    // Region/City zones as {id, city, region, offset}, sorted by city, filtered by city,
    // region or id. An empty query returns them all.
    Q_INVOKABLE QVariantList search(const QString &query) const;
    Q_INVOKABLE QString      displayName(const QString &zoneId) const;

  private:
    QVariantList m_zones;
};
