// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Device bridges ported from Atlantic's qt5-plugin:
//   GeolocationBridge          WebKitGeolocationManager <- Qt Positioning (SFOS
//                              has no GeoClue2, WebKit's built-in provider)
//   DeviceOrientationBridge    DeviceOrientation/DeviceMotion <- Qt Sensors
//                              (sensorfw), through Atlantic's engine patch
//   ClipboardBridge            page clipboard writes -> QClipboard, through
//                              Atlantic's engine patch
// The last two use entry points that only Atlantic's WebKit build exports
// (wpe_sfos_*, wpe_qt_set_clipboard_write_hook). They are looked up at run
// time, so the view also runs on an engine without them; the bridges are
// then inactive.

#pragma once

#include <QObject>

#include <dlfcn.h>
#include <wpe/webkit.h>

// An engine entry point. Qt loads this plugin RTLD_LOCAL, and musl's
// RTLD_DEFAULT does not search the libraries it brought in.
inline void *engineSymbol(const char *name) {
    static void *const engine = dlopen("libWPEWebKit-2.0.so.1", RTLD_NOW | RTLD_NOLOAD);
    return dlsym(engine ? engine : RTLD_DEFAULT, name);
}

class QGeoPositionInfo;
class QGeoPositionInfoSource;
class QAccelerometer;
class QGyroscope;
class QRotationSensor;

class GeolocationBridge final : public QObject {
    Q_OBJECT

  public:
    static void attach(WebKitWebContext *context);

  private:
    explicit GeolocationBridge(WebKitGeolocationManager *manager);
    void                      start();
    void                      stop();
    void                      positionUpdated(const QGeoPositionInfo &info);

    WebKitGeolocationManager *m_manager;
    QGeoPositionInfoSource   *m_source = nullptr;
};

class DeviceOrientationBridge final : public QObject {
    Q_OBJECT

  public:
    static bool available();
    static void attach(WebKitWebView *view);

  private:
    explicit DeviceOrientationBridge(WebKitWebView *view);
    ~DeviceOrientationBridge() override;
    void             setNeeded(bool orientation, bool motion);
    void             rotationChanged();
    void             motionChanged();

    WebKitWebView   *m_view;
    QRotationSensor *m_rotation            = nullptr;
    QAccelerometer  *m_accelerometer       = nullptr;
    QAccelerometer  *m_linearAccelerometer = nullptr;
    QGyroscope      *m_gyroscope           = nullptr;
    bool             m_orientationActive   = false;
    bool             m_motionActive        = false;
};

namespace ClipboardBridge {
    // Routes page clipboard writes to QClipboard. Idempotent; true when the
    // engine has the hook.
    bool ensure();
} // namespace ClipboardBridge
