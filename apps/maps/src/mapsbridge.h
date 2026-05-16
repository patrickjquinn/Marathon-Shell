#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// MapsBridge — QWebChannel object bridging MapLibre GL JS (running
// inside the Maps app's WebEngineView) to the surrounding QML chrome.
//
// Direction of traffic
// ────────────────────
// • QML → JS  : QML calls runJavaScript("MarathonMaps.setCenter(…)")
//               on the WebEngineView. We don't model that here; it's
//               just a runJavaScript call from QML to the JS facade
//               window.MarathonMaps.* defined in apps/maps/web/maps.html.
//
// • JS  → QML : JS invokes `window.MarathonBridge.<slot>` after the
//               QWebChannel handshake. Those calls land in this object
//               as Q_INVOKABLE slots, which then emit Qt signals that
//               the QML side connects to.
//
// Keep this class deliberately thin — the map state lives in JS for
// performance; QML owns search, the place card, routing, navigation
// state, voice cues. Anything richer should be a separate
// JsonRoute/JsonManeuver value type, not pushed through here.
class MapsBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(MapsBridge)

  public:
    explicit MapsBridge(QObject *parent = nullptr);

  public slots:
    // Called by JS once MapLibre's `style.load` has fired and the
    // QWebChannel transport is initialised. QML waits for this before
    // pushing the first setCenter() / setUserLocation() commands;
    // otherwise the calls evaluate before window.MarathonMaps exists
    // and silently no-op.
    void notifyReady();

    // User tapped the basemap (not a pin). Lat/Lon are in WGS84. QML
    // uses this for long-press-to-drop-a-pin and reverse-geocode flows.
    void onMapClicked(double latitude, double longitude);

    // User tapped a destination/result pin previously added with
    // window.MarathonMaps.addPin(). `id` matches what QML passed in,
    // so the QML side can correlate to its searchResults model.
    void onPinTapped(const QString &id);

    // Map view moved (pan or zoom settled). QML uses this to invalidate
    // a "recentre" pill (showing it whenever the user has drifted off
    // their live coordinate).
    void onMapMoved(double centerLat, double centerLon, double zoom);

  signals:
    void ready();
    void mapClicked(double latitude, double longitude);
    void pinTapped(const QString &id);
    void mapMoved(double centerLat, double centerLon, double zoom);
};
