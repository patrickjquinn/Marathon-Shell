#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlregistration.h>

// ValhallaRoutingClient — POSTs route requests to the public
// `valhalla1.openstreetmap.de` instance and exposes the parsed result
// (decoded polyline as GeoJSON, maneuver list, duration/distance) to
// QML.
//
// Why hosted Valhalla and not local OSRM/GraphHopper:
//   • Free, no API key, OSM-derived, supports auto/pedestrian/bicycle
//     costings with full maneuver semantics including verbal_*
//     instructions the Piper TTS layer reads back.
//   • Single round-trip per route — no need to ship a routing engine
//     binary or world-sized tile data in the Marathon image. Future
//     work can swap to a local Valhalla daemon by reskinning the URL.
//   • Same data model as Mapbox Directions API, so the maneuver list
//     UI maps cleanly.
//
// Geometry note: Valhalla emits a Google-style encoded polyline at
// precision 6 (not 5 like Mapbox). We decode to a GeoJSON
// LineString string so the bridge can hand it straight to
// `map.getSource("marathon-route").setData(json)` on the JS side.
class ValhallaRoutingClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(ValhallaRoutingClient)
    Q_PROPERTY(bool routing READ routing NOTIFY routingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantMap currentRoute READ currentRoute NOTIFY routeReady)

  public:
    explicit ValhallaRoutingClient(QObject *parent = nullptr);

    bool routing() const {
        return m_routing;
    }
    QString lastError() const {
        return m_lastError;
    }
    QVariantMap currentRoute() const {
        return m_currentRoute;
    }

    // mode: "auto" | "pedestrian" | "bicycle" (Valhalla costing names).
    Q_INVOKABLE void requestRoute(double startLat, double startLon, double endLat, double endLon,
                                  const QString &mode = "auto");

    Q_INVOKABLE void clearRoute();

  signals:
    void routingChanged();
    void lastErrorChanged();
    // routeReady fires after a successful response. `geojson` is the
    // GeoJSON LineString string the WebEngineView consumes;
    // `maneuvers` is a QVariantList of QVariantMaps each with the
    // keys the active-nav banner + maneuver-list sheet need
    // (instruction, type, length, time, verbalPre, verbalPost).
    void routeReady(const QString &geojson, const QVariantList &maneuvers, double durationSec,
                    double distanceMeters, const QVariantMap &summary);
    void routeFailed(const QString &error);

  private:
    void                  onReply();
    static QVariantList   decodePolylineToCoords(const QString &encoded, int precision = 6);
    static QString        coordsToGeoJsonLineString(const QVariantList &coords);

    QNetworkAccessManager m_nam;
    bool                  m_routing = false;
    QString               m_lastError;
    QVariantMap           m_currentRoute;
};
