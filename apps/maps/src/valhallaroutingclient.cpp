#include "valhallaroutingclient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace {
    constexpr const char *kValhallaUrl = "https://valhalla1.openstreetmap.de/route";
} // namespace

ValhallaRoutingClient::ValhallaRoutingClient(QObject *parent)
    : QObject(parent) {}

void ValhallaRoutingClient::requestRoute(double startLat, double startLon, double endLat,
                                         double endLon, const QString &mode) {
    if (m_routing)
        return;

    QJsonObject body;
    QJsonArray  locations;
    QJsonObject start, end;
    start.insert(QStringLiteral("lat"), startLat);
    start.insert(QStringLiteral("lon"), startLon);
    end.insert(QStringLiteral("lat"), endLat);
    end.insert(QStringLiteral("lon"), endLon);
    locations.append(start);
    locations.append(end);

    body.insert(QStringLiteral("locations"), locations);
    body.insert(QStringLiteral("costing"), mode.isEmpty() ? QString("auto") : mode);
    body.insert(QStringLiteral("units"), QStringLiteral("kilometers"));
    QJsonObject directions;
    directions.insert(QStringLiteral("language"), QStringLiteral("en-US"));
    directions.insert(QStringLiteral("units"), QStringLiteral("kilometers"));
    body.insert(QStringLiteral("directions_options"), directions);

    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkRequest  req((QUrl(kValhallaUrl)));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("User-Agent", "MarathonOS/1.0 (Maps app routing)");

    QNetworkReply *reply = m_nam.post(req, payload);
    connect(reply, &QNetworkReply::finished, this, &ValhallaRoutingClient::onReply);
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);

    m_routing = true;
    emit routingChanged();
}

void ValhallaRoutingClient::clearRoute() {
    m_currentRoute.clear();
    m_lastError.clear();
    emit routeReady("", QVariantList(), 0.0, 0.0, QVariantMap());
    emit lastErrorChanged();
}

void ValhallaRoutingClient::onReply() {
    auto *reply = qobject_cast<QNetworkReply *>(sender());
    m_routing   = false;
    emit routingChanged();

    if (!reply || reply->error() != QNetworkReply::NoError) {
        m_lastError = reply ? reply->errorString() : QStringLiteral("Unknown network error");
        emit lastErrorChanged();
        emit routeFailed(m_lastError);
        return;
    }

    const QByteArray    raw = reply->readAll();
    QJsonParseError     perr;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
    if (perr.error != QJsonParseError::NoError) {
        m_lastError = QStringLiteral("Parse error: %1").arg(perr.errorString());
        emit lastErrorChanged();
        emit routeFailed(m_lastError);
        return;
    }

    const QJsonObject root = doc.object();
    const QJsonObject trip = root.value("trip").toObject();
    const QJsonArray  legs = trip.value("legs").toArray();
    if (legs.isEmpty()) {
        m_lastError = QStringLiteral("Valhalla returned an empty trip");
        emit lastErrorChanged();
        emit routeFailed(m_lastError);
        return;
    }

    // Valhalla's response is single-leg for a 2-stop request, so we
    // pull the first leg. Future multi-stop directions would loop.
    const QJsonObject  leg     = legs.first().toObject();
    const QString      shape   = leg.value("shape").toString();
    const QJsonArray   manArr  = leg.value("maneuvers").toArray();
    const QJsonObject  summary = leg.value("summary").toObject();

    const QVariantList coords  = decodePolylineToCoords(shape, 6);
    const QString      geojson = coordsToGeoJsonLineString(coords);

    QVariantList       maneuvers;
    maneuvers.reserve(manArr.size());
    for (const QJsonValue &v : manArr) {
        const QJsonObject m = v.toObject();
        QVariantMap       out;
        out["instruction"] = m.value("instruction").toString();
        out["type"]        = m.value("type").toInt();
        out["length"]      = m.value("length").toDouble(); // km
        out["time"]        = m.value("time").toDouble();   // seconds
        out["verbalPre"]   = m.value("verbal_pre_transition_instruction").toString();
        out["verbalPost"]  = m.value("verbal_post_transition_instruction").toString();
        out["streetNames"] = m.value("street_names").toVariant();
        // Maneuver point — Valhalla emits the begin_shape_index that
        // indexes into the polyline, so the active-nav banner can
        // know where the turn happens on the route.
        out["beginShapeIndex"] = m.value("begin_shape_index").toInt();
        out["endShapeIndex"]   = m.value("end_shape_index").toInt();
        maneuvers.append(out);
    }

    QVariantMap summaryMap;
    summaryMap["time"]     = summary.value("time").toDouble();
    summaryMap["distance"] = summary.value("length").toDouble();
    summaryMap["minLat"]   = summary.value("min_lat").toDouble();
    summaryMap["minLon"]   = summary.value("min_lon").toDouble();
    summaryMap["maxLat"]   = summary.value("max_lat").toDouble();
    summaryMap["maxLon"]   = summary.value("max_lon").toDouble();

    m_currentRoute.clear();
    m_currentRoute["geojson"]   = geojson;
    m_currentRoute["maneuvers"] = maneuvers;
    m_currentRoute["duration"]  = summary.value("time").toDouble();
    m_currentRoute["distance"]  = summary.value("length").toDouble() * 1000.0; // km → m
    m_currentRoute["summary"]   = summaryMap;

    emit routeReady(geojson, maneuvers, summary.value("time").toDouble(),
                    summary.value("length").toDouble() * 1000.0, summaryMap);
}

// Decode Google-style polyline. Valhalla uses precision 6 (not 5).
// Spec: https://valhalla.github.io/valhalla/decoding/
QVariantList ValhallaRoutingClient::decodePolylineToCoords(const QString &encoded, int precision) {
    QVariantList coords;
    if (encoded.isEmpty())
        return coords;

    const double     factor = std::pow(10.0, precision);
    qint64           lat    = 0;
    qint64           lon    = 0;
    int              i      = 0;
    const QByteArray bytes  = encoded.toLatin1();
    while (i < bytes.size()) {
        // Lat
        int    shift  = 0;
        qint64 result = 0;
        int    b;
        do {
            b = bytes[i++] - 63;
            result |= (qint64(b & 0x1f)) << shift;
            shift += 5;
        } while (b >= 0x20 && i < bytes.size());
        const qint64 dlat = (result & 1) ? ~(result >> 1) : (result >> 1);
        lat += dlat;

        // Lon
        shift  = 0;
        result = 0;
        do {
            b = bytes[i++] - 63;
            result |= (qint64(b & 0x1f)) << shift;
            shift += 5;
        } while (b >= 0x20 && i < bytes.size());
        const qint64 dlon = (result & 1) ? ~(result >> 1) : (result >> 1);
        lon += dlon;

        // GeoJSON convention is [lon, lat]; emit in that order so the
        // string-builder below can splice with no further work.
        QVariantList pair;
        pair << (lon / factor);
        pair << (lat / factor);
        coords.append(QVariant::fromValue(pair));
    }
    return coords;
}

QString ValhallaRoutingClient::coordsToGeoJsonLineString(const QVariantList &coords) {
    QJsonArray points;
    for (const QVariant &p : coords) {
        const QVariantList pair = p.toList();
        if (pair.size() != 2)
            continue;
        QJsonArray entry;
        entry.append(pair.at(0).toDouble());
        entry.append(pair.at(1).toDouble());
        points.append(entry);
    }
    QJsonObject geometry;
    geometry["type"]        = "LineString";
    geometry["coordinates"] = points;
    QJsonObject feature;
    feature["type"]       = "Feature";
    feature["geometry"]   = geometry;
    feature["properties"] = QJsonObject();
    QJsonObject fc;
    fc["type"] = "FeatureCollection";
    QJsonArray features;
    features.append(feature);
    fc["features"] = features;
    return QString::fromUtf8(QJsonDocument(fc).toJson(QJsonDocument::Compact));
}
