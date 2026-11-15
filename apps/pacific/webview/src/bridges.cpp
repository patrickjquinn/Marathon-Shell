// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "bridges.h"

#include <QClipboard>
#include <QGeoPositionInfoSource>
#include <QGuiApplication>
#include <QSet>
#include <QtGlobal>

#ifdef PACIFIC_HAVE_SENSORS
#include <QAccelerometer>
#include <QGyroscope>
#include <QRotationSensor>
#endif

#include <cmath>
#include <dlfcn.h>

// --- Geolocation -----------------------------------------------------------

void GeolocationBridge::attach(WebKitWebContext* context)
{
    if (!context)
        return;
    WebKitGeolocationManager* manager = webkit_web_context_get_geolocation_manager(context);
    if (g_object_get_data(G_OBJECT(manager), "pacific-geolocation-bridge"))
        return;
    auto* bridge = new GeolocationBridge(manager);
    g_object_set_data_full(G_OBJECT(manager), "pacific-geolocation-bridge", bridge,
        [](gpointer data) { delete static_cast<GeolocationBridge*>(data); });
}

GeolocationBridge::GeolocationBridge(WebKitGeolocationManager* manager)
    : m_manager(manager)
{
    // Handling "start" makes WebKit skip its GeoClue2 provider and take
    // positions from webkit_geolocation_manager_update_position().
    g_signal_connect_swapped(manager, "start",
        G_CALLBACK(+[](GeolocationBridge* self) -> gboolean { self->start(); return TRUE; }), this);
    g_signal_connect_swapped(manager, "stop", G_CALLBACK(+[](GeolocationBridge* self) { self->stop(); }), this);
}

void GeolocationBridge::start()
{
    if (!m_source) {
        m_source = QGeoPositionInfoSource::createDefaultSource(this);
        if (!m_source) {
            webkit_geolocation_manager_failed(m_manager, "No position source available");
            return;
        }
        connect(m_source, &QGeoPositionInfoSource::positionUpdated, this, &GeolocationBridge::positionUpdated);
        connect(m_source, &QGeoPositionInfoSource::errorOccurred, this, [this](QGeoPositionInfoSource::Error) {
            webkit_geolocation_manager_failed(m_manager, "Position source error");
        });
    }
    m_source->setPreferredPositioningMethods(webkit_geolocation_manager_get_enable_high_accuracy(m_manager)
            ? QGeoPositionInfoSource::AllPositioningMethods
            : QGeoPositionInfoSource::NonSatellitePositioningMethods);
    m_source->startUpdates();
    // A fast, possibly stale fix while the GPS warms up.
    const QGeoPositionInfo last = m_source->lastKnownPosition();
    if (last.isValid())
        positionUpdated(last);
}

void GeolocationBridge::stop()
{
    if (m_source)
        m_source->stopUpdates();
}

void GeolocationBridge::positionUpdated(const QGeoPositionInfo& info)
{
    const QGeoCoordinate c = info.coordinate();
    if (!c.isValid())
        return;
    const double accuracy = info.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
        ? info.attribute(QGeoPositionInfo::HorizontalAccuracy)
        : 1000;
    WebKitGeolocationPosition* position = webkit_geolocation_position_new(c.latitude(), c.longitude(), accuracy);
    if (info.timestamp().isValid())
        webkit_geolocation_position_set_timestamp(position, static_cast<guint64>(info.timestamp().toSecsSinceEpoch()));
    if (c.type() == QGeoCoordinate::Coordinate3D) {
        webkit_geolocation_position_set_altitude(position, c.altitude());
        if (info.hasAttribute(QGeoPositionInfo::VerticalAccuracy))
            webkit_geolocation_position_set_altitude_accuracy(position, info.attribute(QGeoPositionInfo::VerticalAccuracy));
    }
    if (info.hasAttribute(QGeoPositionInfo::GroundSpeed))
        webkit_geolocation_position_set_speed(position, info.attribute(QGeoPositionInfo::GroundSpeed));
    if (info.hasAttribute(QGeoPositionInfo::Direction))
        webkit_geolocation_position_set_heading(position, info.attribute(QGeoPositionInfo::Direction));
    webkit_geolocation_manager_update_position(m_manager, position);
    webkit_geolocation_position_free(position);
}

// --- Device orientation / motion (Atlantic engine ABI) -----------------------

namespace {
using SensorsCallback = void (*)(gboolean, gboolean, gpointer);
using SetSensorsCallbackFn = void (*)(WebKitWebView*, SensorsCallback, gpointer);
using OrientationChangedFn = void (*)(WebKitWebView*, double, double, double, gboolean);
using MotionChangedFn = void (*)(WebKitWebView*, double, double, double, double, double, double, double, double, double, double);

struct SensorAbi {
    SetSensorsCallbackFn setCallback = nullptr;
    OrientationChangedFn orientation = nullptr;
    MotionChangedFn motion = nullptr;
};

const SensorAbi& sensorAbi()
{
    static const SensorAbi abi = [] {
        SensorAbi a;
        a.setCallback = reinterpret_cast<SetSensorsCallbackFn>(engineSymbol("wpe_sfos_set_device_sensors_callback"));
        a.orientation = reinterpret_cast<OrientationChangedFn>(engineSymbol("wpe_sfos_device_orientation_changed"));
        a.motion = reinterpret_cast<MotionChangedFn>(engineSymbol("wpe_sfos_device_motion_changed"));
        if (!a.setCallback || !a.orientation || !a.motion)
            a = SensorAbi();
        return a;
    }();
    return abi;
}

// Fold an angle in degrees into [-180, 180).
double wrapTo180(double degrees)
{
    double wrapped = std::fmod(degrees + 180.0, 360.0);
    if (wrapped < 0)
        wrapped += 360.0;
    return wrapped - 180.0;
}

constexpr int kMotionRateHz = 60;
constexpr int kOrientationRateHz = 30;
} // namespace

bool DeviceOrientationBridge::available()
{
#ifdef PACIFIC_HAVE_SENSORS
    return sensorAbi().setCallback != nullptr;
#else
    return false;
#endif
}

void DeviceOrientationBridge::attach(WebKitWebView* view)
{
    if (!view || !available() || g_object_get_data(G_OBJECT(view), "pacific-orientation-bridge"))
        return;
    auto* bridge = new DeviceOrientationBridge(view);
    g_object_set_data_full(G_OBJECT(view), "pacific-orientation-bridge", bridge, [](gpointer data) {
        // Runs while the view itself is being destroyed: calling back into it
        // to unregister reaches a dead page proxy (Atlantic: crashed the UI
        // process on every tab close), so drop the back-pointer first.
        auto* self = static_cast<DeviceOrientationBridge*>(data);
        self->m_view = nullptr;
        delete self;
    });
}

DeviceOrientationBridge::DeviceOrientationBridge(WebKitWebView* view)
    : m_view(view)
{
    sensorAbi().setCallback(view, [](gboolean orientation, gboolean motion, gpointer data) {
        static_cast<DeviceOrientationBridge*>(data)->setNeeded(orientation != FALSE, motion != FALSE);
    }, this);
}

DeviceOrientationBridge::~DeviceOrientationBridge()
{
    if (m_view && sensorAbi().setCallback)
        sensorAbi().setCallback(m_view, nullptr, nullptr);
}

void DeviceOrientationBridge::setNeeded(bool orientation, bool motion)
{
#ifdef PACIFIC_HAVE_SENSORS
    if (orientation != m_orientationActive) {
        if (orientation) {
            if (!m_rotation) {
                m_rotation = new QRotationSensor(this);
                m_rotation->setHasZ(true);
                m_rotation->setDataRate(kOrientationRateHz);
                connect(m_rotation, &QRotationSensor::readingChanged, this, &DeviceOrientationBridge::rotationChanged);
            }
            m_rotation->start();
        } else if (m_rotation) {
            m_rotation->stop();
        }
        m_orientationActive = orientation;
    }
    if (motion == m_motionActive)
        return;
    if (motion) {
        if (!m_accelerometer) {
            m_accelerometer = new QAccelerometer(this);
            m_accelerometer->setDataRate(kMotionRateHz);
            connect(m_accelerometer, &QAccelerometer::readingChanged, this, &DeviceOrientationBridge::motionChanged);
            // Acceleration without gravity needs a second sensor in User mode;
            // without one the field stays NaN, which WebKit reports as null.
            auto* linear = new QAccelerometer(this);
            if (linear->isFeatureSupported(QSensor::AccelerationMode)) {
                linear->setAccelerationMode(QAccelerometer::User);
                linear->setDataRate(kMotionRateHz);
                m_linearAccelerometer = linear;
            } else {
                delete linear;
            }
            m_gyroscope = new QGyroscope(this);
            m_gyroscope->setDataRate(kMotionRateHz);
        }
        m_accelerometer->start();
        if (m_linearAccelerometer)
            m_linearAccelerometer->start();
        m_gyroscope->start();
    } else {
        if (m_accelerometer)
            m_accelerometer->stop();
        if (m_linearAccelerometer)
            m_linearAccelerometer->stop();
        if (m_gyroscope)
            m_gyroscope->stop();
    }
    m_motionActive = motion;
#else
    Q_UNUSED(orientation)
    Q_UNUSED(motion)
#endif
}

void DeviceOrientationBridge::rotationChanged()
{
#ifdef PACIFIC_HAVE_SENSORS
    QRotationReading* reading = m_rotation ? m_rotation->reading() : nullptr;
    if (!reading || !m_view || !sensorAbi().orientation)
        return;
    // Axis mapping measured by Atlantic on sensorfw (Xperia 10 II) against
    // gravity: y is the W3C gamma offset by 180 and x is beta negated. Re-check
    // on the Jolla Phone before trusting it there.
    double beta = wrapTo180(-reading->x());
    double gamma = wrapTo180(reading->y() - 180.0);
    if (gamma > 90.0) {
        gamma = 180.0 - gamma;
        beta = wrapTo180(180.0 - beta);
    } else if (gamma < -90.0) {
        gamma = -180.0 - gamma;
        beta = wrapTo180(180.0 - beta);
    }
    const bool absolute = m_rotation->hasZ();
    double alpha = NAN;
    if (absolute) {
        alpha = std::fmod(reading->z(), 360.0);
        if (alpha < 0)
            alpha += 360.0;
    }
    sensorAbi().orientation(m_view, alpha, beta, gamma, absolute ? TRUE : FALSE);
#endif
}

void DeviceOrientationBridge::motionChanged()
{
#ifdef PACIFIC_HAVE_SENSORS
    QAccelerometerReading* reading = m_accelerometer ? m_accelerometer->reading() : nullptr;
    if (!reading || !m_view || !sensorAbi().motion)
        return;
    double x = NAN;
    double y = NAN;
    double z = NAN;
    if (m_linearAccelerometer) {
        if (QAccelerometerReading* linear = m_linearAccelerometer->reading()) {
            x = linear->x();
            y = linear->y();
            z = linear->z();
        }
    }
    double alphaRate = NAN;
    double betaRate = NAN;
    double gammaRate = NAN;
    if (m_gyroscope) {
        if (QGyroscopeReading* gyro = m_gyroscope->reading()) {
            alphaRate = gyro->z();
            betaRate = gyro->x();
            gammaRate = gyro->y();
        }
    }
    const int rate = m_accelerometer->dataRate();
    sensorAbi().motion(m_view, x, y, z, reading->x(), reading->y(), reading->z(), alphaRate, betaRate, gammaRate,
        rate > 0 ? 1000.0 / rate : NAN);
#endif
}

// --- Clipboard (Atlantic engine ABI) ----------------------------------------

bool ClipboardBridge::ensure()
{
    static const bool hooked = [] {
        if (qEnvironmentVariableIntValue("PACIFIC_DISABLE_CLIPBOARD_BRIDGE") == 1)
            return false;
        using HookFn = void (*)(void (*)(const char*));
        auto hook = reinterpret_cast<HookFn>(engineSymbol("wpe_qt_set_clipboard_write_hook"));
        if (!hook)
            return false;
        // Called on the GUI thread, where the pasteboard IPC is dispatched.
        hook([](const char* text) {
            if (text && QGuiApplication::clipboard())
                QGuiApplication::clipboard()->setText(QString::fromUtf8(text));
        });
        return true;
    }();
    return hooked;
}
