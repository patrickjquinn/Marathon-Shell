// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "graphics.h"

#include <QGuiApplication>
#include <qpa/qplatformintegration.h>
#include <private/qguiapplication_p.h>

namespace keel {

QString openGLUnavailableReason()
{
    QPlatformIntegration *integration = QGuiApplicationPrivate::platformIntegration();
    if (integration && integration->hasCapability(QPlatformIntegration::OpenGL))
        return QString();
    return QStringLiteral("the Qt platform plugin \"%1\" has no OpenGL support. keel-shell "
                          "draws its Lipstick windows with Qt Quick, which needs OpenGL ES "
                          "(EGL); run it under a Wayland compositor with QT_QPA_PLATFORM="
                          "wayland-egl, as Lipstick provides")
            .arg(QGuiApplication::platformName());
}

QString sceneGraphFailureMessage(int windowId, WindowRole role, const QString &qtMessage)
{
    return QStringLiteral("cannot render Lipstick window %1 (%2): %3")
            .arg(windowId).arg(windowRoleName(role), qtMessage.trimmed());
}

} // namespace keel
