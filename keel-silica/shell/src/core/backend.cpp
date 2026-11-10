// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "backend.h"

#include <QCloseEvent>
#include <QGuiApplication>
#include <QScreen>

#include "lipstickwindow.h"
#include "logging.h"
#include "orientation.h"
#include "shellstate.h"

namespace keel {

Backend::Backend(ShellState *state, QObject *parent)
    : QObject(parent)
    , m_state(state)
{
    connect(m_state, &ShellState::contentOrientationChanged,
            this, &Backend::onContentOrientationChanged);
    connect(m_state, &ShellState::activateRequested, this, &Backend::onActivateRequested);
    trackScreen(QGuiApplication::primaryScreen());
}

Backend::~Backend()
= default;

void Backend::setConfig(const BackendConfig &config)
{
    m_config = config;
    m_mapper.setCoverEnabled(config.coverEnabled);
    m_mapper.setCoverPolicy(CoverPolicy(config.coverTitle));
}

void Backend::logDecision(const QString &message) const
{
    qCDebug(lcKeelShell).noquote() << message;
}

void Backend::reportFatalError(const QString &message)
{
    if (m_error.isEmpty())
        m_error = message;
    emit fatalError(message);
}

void Backend::trackScreen(QScreen *screen)
{
    if (!screen || screen == m_screen)
        return;
    if (m_screen)
        disconnect(m_screen.data(), nullptr, this, nullptr);
    m_screen = screen;
    screen->setOrientationUpdateMask(Qt::PortraitOrientation | Qt::LandscapeOrientation
                                     | Qt::InvertedPortraitOrientation
                                     | Qt::InvertedLandscapeOrientation);
    connect(screen, &QScreen::orientationChanged, this, &Backend::onScreenOrientationChanged);
    onScreenOrientationChanged(screen->orientation());
}

void Backend::onScreenOrientationChanged(Qt::ScreenOrientation orientation)
{
    if (!m_screen)
        return;
    m_state->setOrientation(orientationToAngle(orientation, m_screen->primaryOrientation()));
}

void Backend::onContentOrientationChanged(int degrees)
{
    const Qt::ScreenOrientation primary = m_screen ? m_screen->primaryOrientation()
                                                   : Qt::PortraitOrientation;
    const Qt::ScreenOrientation o = angleToOrientation(degrees, primary);
    for (auto it = m_outer.constBegin(); it != m_outer.constEnd(); ++it) {
        // Covers are drawn by Lipstick in its own orientation.
        if (it.value() && m_roles.value(it.key()) != WindowRole::Cover)
            it.value()->reportContentOrientationChange(o);
    }
}

void Backend::onActivateRequested()
{
    QWindow *main = m_outer.value(WindowMapper::MainWindowId);
    if (!main)
        return;
    if (!main->isVisible())
        main->show();
    main->raise();
    main->requestActivate();
}

void Backend::registerOuterWindow(int windowId, WindowRole role, QWindow *window)
{
    m_outer.insert(windowId, window);
    m_roles.insert(windowId, role);
    window->installEventFilter(this);
    connect(window, &QWindow::activeChanged, this, &Backend::updateActive);
    connect(window, &QWindow::screenChanged, this, &Backend::trackScreen);
    if (role == WindowRole::Cover)
        m_state->setCoverStatus(ShellState::CoverInactive);
}

void Backend::showOuterWindow(int windowId)
{
    QWindow *window = m_outer.value(windowId);
    if (!window)
        return;
    const WindowRole role = m_roles.value(windowId);
    if (!window->handle()) {
        QString title = m_config.windowTitle;
        if (role == WindowRole::Cover && !title.isEmpty())
            title += QStringLiteral(" cover");
        LipstickWindow::prepare(window, role, title);
    }
    const bool fullScreen = role != WindowRole::Cover
            && QGuiApplication::platformName().startsWith(QLatin1String("wayland"))
            && QGuiApplication::primaryScreen();
    if (fullScreen)
        window->showFullScreen();
    else
        window->show();
    logDecision(QStringLiteral("outer window %1 (%2) shown, CATEGORY=%3")
                .arg(windowId).arg(windowRoleName(role))
                .arg(window->property("CATEGORY").toString()));
    emit outerWindowShown(windowId, role, window);
}

void Backend::unregisterOuterWindow(int windowId)
{
    QWindow *window = m_outer.take(windowId);
    const WindowRole role = m_roles.take(windowId);
    if (window) {
        window->removeEventFilter(this);
        disconnect(window, nullptr, this, nullptr);
    }
    if (role == WindowRole::Cover)
        m_state->setCoverStatus(ShellState::CoverInactive);
    emit outerWindowHidden(windowId);
    updateActive();
}

int Backend::windowIdFor(QObject *window) const
{
    for (auto it = m_outer.constBegin(); it != m_outer.constEnd(); ++it) {
        if (it.value() == window)
            return it.key();
    }
    return 0;
}

void Backend::updateActive()
{
    bool active = false;
    for (auto it = m_outer.constBegin(); it != m_outer.constEnd(); ++it) {
        if (it.value() && it.value()->isActive() && m_roles.value(it.key()) != WindowRole::Cover) {
            active = true;
            break;
        }
    }
    m_state->setActive(active);
    QWindow *w = qobject_cast<QWindow *>(sender());
    if (w && w->isActive()) {
        const int id = windowIdFor(w);
        if (id)
            outerWindowActivated(id);
    }
}

bool Backend::eventFilter(QObject *watched, QEvent *event)
{
    const int id = windowIdFor(watched);
    if (id) {
        const WindowRole role = m_roles.value(id);
        if (event->type() == QEvent::Expose && role == WindowRole::Cover) {
            auto *w = static_cast<QWindow *>(watched);
            m_state->setCoverStatus(w->isExposed() ? ShellState::CoverActive
                                                   : ShellState::CoverInactive);
        } else if (event->type() == QEvent::Close && role == WindowRole::Main) {
            // Keep the window; let the app decide (CloseRequested), then the
            // runner terminates it after the grace period.
            event->ignore();
            emit closeRequested();
            return true;
        } else if (event->type() == QEvent::Close && role != WindowRole::Main) {
            event->ignore();
            return true;
        }
    }
    return QObject::eventFilter(watched, event);
}

} // namespace keel
