// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Compositor-API adapter boundary. Everything that depends on a particular
// QtWayland compositor API lives in a Backend subclass:
//   src/backend/qt56/   Sailfish system Qt 5.6.3, QtCompositor (pre-1.0 API)
//   src/backend/qt515/  Qt 5.15 QtWaylandCompositor (host build and tests)
// Backend (this class) owns the behaviour shared by both: window mapping,
// Lipstick window tagging, activation, orientation, cover status and close
// handling for the outer (Lipstick-facing) QWindows.

#ifndef KEEL_BACKEND_H
#define KEEL_BACKEND_H

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QWindow>

#include "surfaceinfo.h"
#include "windowmapper.h"

class QScreen;

namespace keel {

class ShellState;

struct BackendConfig {
    QString socketName;
    QString windowTitle;
    bool followKeyboard = false;
    bool coverEnabled = true;
    QString coverTitle;
};

class Backend : public QObject
{
    Q_OBJECT
public:
    explicit Backend(ShellState *state, QObject *parent = nullptr);
    ~Backend() override;

    // Creates the compositor socket and shows the main window.
    virtual bool start(const BackendConfig &config) = 0;
    virtual QString socketName() const = 0;
    virtual QString name() const = 0;

    WindowMapper *mapper() { return &m_mapper; }
    ShellState *state() const { return m_state; }
    const BackendConfig &config() const { return m_config; }

    // Outer windows by mapper window id (for tests and diagnostics).
    QWindow *outerWindow(int windowId) const { return m_outer.value(windowId); }
    QList<int> outerWindowIds() const { return m_outer.keys(); }

    // The first fatal error (e.g. no OpenGL for the Lipstick windows), or empty.
    QString errorString() const { return m_error; }

signals:
    // Lipstick asked the main window to close (user closed the app).
    void closeRequested();
    // Diagnostics: an outer window was shown / hidden.
    void outerWindowShown(int windowId, keel::WindowRole role, QWindow *window);
    void outerWindowHidden(int windowId);
    // keel-shell cannot go on (e.g. an outer window has no OpenGL context).
    // start() returns false for errors during start-up; later ones arrive
    // only through this signal.
    void fatalError(const QString &message);

protected:
    // Subclasses call these around creating/destroying their QWindows.
    void registerOuterWindow(int windowId, WindowRole role, QWindow *window);
    void unregisterOuterWindow(int windowId);
    // Prepares (CATEGORY etc.) and shows a registered outer window.
    void showOuterWindow(int windowId);

    // Called when an outer window becomes the active Lipstick window.
    virtual void outerWindowActivated(int windowId) { Q_UNUSED(windowId) }

    bool eventFilter(QObject *watched, QEvent *event) override;

    void setConfig(const BackendConfig &config);
    // Debug output of lcKeelShell, enabled by --verbose.
    void logDecision(const QString &message) const;
    // Records the error (the first one is kept) and emits fatalError().
    void reportFatalError(const QString &message);

private slots:
    void onScreenOrientationChanged(Qt::ScreenOrientation orientation);
    void onContentOrientationChanged(int degrees);
    void onActivateRequested();
    void updateActive();

private:
    int windowIdFor(QObject *window) const;
    void trackScreen(QScreen *screen);

    ShellState *m_state;
    WindowMapper m_mapper;
    BackendConfig m_config;
    QHash<int, QPointer<QWindow>> m_outer;
    QHash<int, WindowRole> m_roles;
    QPointer<QScreen> m_screen;
    QString m_error;
};

} // namespace keel

#endif // KEEL_BACKEND_H
