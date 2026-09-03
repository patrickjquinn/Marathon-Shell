#pragma once

#include <QObject>
#include <QString>

// DeviceProfile — the single source of truth for per-device hardware traits
// that the shell cannot reliably probe at runtime (GPU driver stack, GLES
// level, HW MSAA, framebuffer pixel format, panel brightness floor, CPU
// governor policy). Every one of these was previously a hardcoded constant in
// main.cpp / the managers, tuned to the Librem 5's etnaviv/i.MX8 and silently
// applied to ALL devices. Centralising them here lets a device overlay declare
// its own values via /etc/marathon/device-profile.conf so one shell binary
// supports many devices.
//
// Precedence for every field: built-in safe default  <  device-profile.conf
// <  explicit MARATHON_* env override (env always wins, for dev/test).
//
// Loaded once, early in main() — BEFORE QGuiApplication — because the default
// QSurfaceFormat has to be decided from glesLevel()/surfaceHasAlpha() before
// the GUI stack comes up. Construction only reads a file, so it is safe with
// no running event loop. Also registered as a QML singleton for the UI layer.
class DeviceProfile : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString deviceId READ deviceId CONSTANT)
    Q_PROPERTY(QString gpuStack READ gpuStack CONSTANT)
    Q_PROPERTY(int glesMajor READ glesMajor CONSTANT)
    Q_PROPERTY(int glesMinor READ glesMinor CONSTANT)
    Q_PROPERTY(bool surfaceHasAlpha READ surfaceHasAlpha CONSTANT)
    Q_PROPERTY(int hwMsaaSamples READ hwMsaaSamples CONSTANT)
    Q_PROPERTY(bool gpuRgba16f READ gpuRgba16f CONSTANT)
    Q_PROPERTY(QString renderNode READ renderNode CONSTANT)
    Q_PROPERTY(QString cpuGovernor READ cpuGovernor CONSTANT)
    Q_PROPERTY(qreal brightnessFloor READ brightnessFloor CONSTANT)
    Q_PROPERTY(int runnerWidth READ runnerWidth CONSTANT)
    Q_PROPERTY(int runnerHeight READ runnerHeight CONSTANT)

  public:
    // Loads (once) from MARATHON_DEVICE_PROFILE if set, else
    // /etc/marathon/device-profile.conf. Missing file → all built-in
    // defaults (which match the historical Librem 5 constants, so behaviour
    // is unchanged on an un-provisioned device). Idempotent.
    static DeviceProfile &instance();

    const QString &deviceId() const {
        return m_deviceId;
    }
    const QString &gpuStack() const {
        return m_gpuStack;
    }
    int glesMajor() const {
        return m_glesMajor;
    }
    int glesMinor() const {
        return m_glesMinor;
    }
    bool surfaceHasAlpha() const {
        return m_surfaceHasAlpha;
    }
    int hwMsaaSamples() const {
        return m_hwMsaaSamples;
    }
    bool gpuRgba16f() const {
        return m_gpuRgba16f;
    }
    const QString &renderNode() const {
        return m_renderNode;
    }
    const QString &cpuGovernor() const {
        return m_cpuGovernor;
    }
    qreal brightnessFloor() const {
        return m_brightnessFloor;
    }
    int runnerWidth() const {
        return m_runnerWidth;
    }
    int runnerHeight() const {
        return m_runnerHeight;
    }

  private:
    explicit DeviceProfile(QObject *parent = nullptr);
    void load();

    QString m_deviceId        = QStringLiteral("generic");
    // Default GPU traits = the historical Librem 5 etnaviv/i.MX8 constants,
    // so an un-provisioned device behaves exactly as before this refactor.
    QString m_gpuStack        = QStringLiteral("mesa-etnaviv");
    int     m_glesMajor       = 2;
    int     m_glesMinor       = 0;
    bool    m_surfaceHasAlpha = false; // i.MX8 LCDIF CRTC is XRGB8888
    int     m_hwMsaaSamples   = 0;     // GC7000Lite reports GL_MAX_SAMPLES <= 1
    bool    m_gpuRgba16f      = false;
    QString m_renderNode      = QStringLiteral("/dev/dri/renderD128");
    QString m_cpuGovernor     = QStringLiteral("ondemand");
    qreal   m_brightnessFloor = 0.28; // L5 panel min visible duty cycle
    // Initial surface size handed to spawned app-runners (their logical
    // app canvas). L5 default 540x1140; the shell forwards these as
    // MARATHON_APP_WIDTH/HEIGHT so an overlay can set a device's own canvas.
    int m_runnerWidth  = 540;
    int m_runnerHeight = 1140;
};
