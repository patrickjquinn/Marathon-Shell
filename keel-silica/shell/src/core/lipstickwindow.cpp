// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "lipstickwindow.h"

#include <QGuiApplication>
#include <QSurfaceFormat>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>
#include <qpa/qplatformwindow.h>

namespace keel {

QString LipstickWindow::categoryFor(WindowRole role)
{
    return role == WindowRole::Cover ? QStringLiteral("cover") : QString();
}

bool LipstickWindow::setWindowProperty(QWindow *window, const QString &name, const QVariant &value)
{
    window->setProperty(name.toLatin1().constData(), value);
    QPlatformWindow *handle = window->handle();
    if (!handle)
        return false;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (native)
        native->setWindowProperty(handle, name, value);
    return true;
}

void LipstickWindow::prepare(QWindow *window, WindowRole role, const QString &title)
{
    // Translucent: Silica app windows let the ambience wallpaper show
    // through; the nested app draws (or not) its own background.
    QSurfaceFormat format = window->requestedFormat();
    format.setAlphaBufferSize(8);
    window->setFormat(format);
    window->setTitle(title);
    window->setProperty("keelRole", windowRoleName(role));

    window->create();

    const QString category = categoryFor(role);
    if (!category.isEmpty())
        setWindowProperty(window, QStringLiteral("CATEGORY"), category);
}

} // namespace keel
