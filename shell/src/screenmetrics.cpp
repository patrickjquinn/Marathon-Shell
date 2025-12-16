#include "screenmetrics.h"

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
