#include "mapsbridge.h"

MapsBridge::MapsBridge(QObject *parent)
    : QObject(parent) {}

void MapsBridge::notifyReady() {
    emit ready();
}

void MapsBridge::onMapClicked(double latitude, double longitude) {
    emit mapClicked(latitude, longitude);
}

void MapsBridge::onPinTapped(const QString &id) {
    emit pinTapped(id);
}

void MapsBridge::onMapMoved(double centerLat, double centerLon, double zoom) {
    emit mapMoved(centerLat, centerLon, zoom);
}

void MapsBridge::onMapError(const QString &message) {
    emit mapError(message);
}
