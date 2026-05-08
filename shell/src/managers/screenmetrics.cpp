#include "screenmetrics.h"

#include <QByteArray>
#include <QGuiApplication>
#include <QScreen>

ScreenMetrics::ScreenMetrics(QObject *parent)
    : QObject(parent) {
    attachToScreen(QGuiApplication::primaryScreen());

    QObject::connect(qApp, &QGuiApplication::primaryScreenChanged, this,
                     [this](QScreen *screen) { attachToScreen(screen); });
}

void ScreenMetrics::attachToScreen(QScreen *screen) {
    if (m_screen == screen) {
        updateFromScreen();
        return;
    }

    if (m_screen) {
        m_screen->disconnect(this);
    }

    m_screen = screen;

    if (m_screen) {
        QObject::connect(m_screen, &QScreen::geometryChanged, this, [this] { updateFromScreen(); });
        QObject::connect(m_screen, &QScreen::availableGeometryChanged, this,
                         [this] { updateFromScreen(); });
        QObject::connect(m_screen, &QScreen::physicalDotsPerInchChanged, this,
                         [this] { updateFromScreen(); });
        QObject::connect(m_screen, &QScreen::logicalDotsPerInchChanged, this,
                         [this] { updateFromScreen(); });
        QObject::connect(m_screen, &QScreen::refreshRateChanged, this,
                         [this] { updateFromScreen(); });
    }

    updateFromScreen();
}

qreal ScreenMetrics::computeDpi(QScreen *screen) const {
    // MARATHON_FORCE_DPI overrides everything below — Qt derives DPI from EDID,
    // and emulated panels (QEMU virtio-gpu, some VM display protocols) report
    // a fake desktop-monitor physical size that yields ~108 DPI on a 720x1440
    // canvas. The shell scales every metric off Constants.scaleFactor = dpi/160,
    // so without this override the UI lands at desktop scale on a phone-shaped
    // screen. Real phone hardware advertises correct EDID, so this env stays
    // unset in production and behavior is unchanged.
    const QByteArray forced = qgetenv("MARATHON_FORCE_DPI");
    if (!forced.isEmpty()) {
        bool        ok      = false;
        const qreal forcedV = forced.toDouble(&ok);
        if (ok && forcedV > 0.0) {
            return forcedV;
        }
    }

    if (!screen) {
        return 0.0;
    }

    qreal dpi = screen->physicalDotsPerInch();
    if (dpi <= 0.0) {
        dpi = screen->logicalDotsPerInch();
    }
    return dpi;
}

void ScreenMetrics::updateFromScreen() {
    int   newWidth            = 0;
    int   newHeight           = 0;
    qreal newDpi              = 0.0;
    qreal newRefreshRate      = 0.0;
    qreal newDevicePixelRatio = 1.0;

    if (m_screen) {
        const QRect geo     = m_screen->geometry();
        newWidth            = geo.width();
        newHeight           = geo.height();
        newDpi              = computeDpi(m_screen);
        newRefreshRate      = m_screen->refreshRate();
        newDevicePixelRatio = m_screen->devicePixelRatio();
    }

    if (newWidth == m_width && newHeight == m_height && qFuzzyCompare(newDpi, m_dpi) &&
        qFuzzyCompare(newRefreshRate, m_refreshRate) &&
        qFuzzyCompare(newDevicePixelRatio, m_devicePixelRatio)) {
        return;
    }

    m_width            = newWidth;
    m_height           = newHeight;
    m_dpi              = newDpi;
    m_refreshRate      = newRefreshRate;
    m_devicePixelRatio = newDevicePixelRatio;
    emit metricsChanged();
}
