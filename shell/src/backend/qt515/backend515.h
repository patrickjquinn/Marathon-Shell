/****************************************************************************
**
** SPDX-FileCopyrightText: 2017 The Qt Company Ltd.
** SPDX-FileCopyrightText: 2023 Artur Gaspar
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Qt 5.15 QtWaylandCompositor backend of keel-shell (host build, tests).
** Structure derived from newcompositor (https://github.com/ArturGaspar/
** newcompositor, src/compositor.*, src/view.*, src/window.*, BSD-3-Clause),
** which in turn derives from the Qt Wayland "minimal-cpp"/"qwindow-compositor"
** examples (BSD). Modified for Shipwright: surface placement is delegated to
** keel::WindowMapper, rendering is raster (wl_shm clients) so it runs on
** headless CI, Xwayland support removed. See PROVENANCE.md.
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are
** met:
**   * Redistributions of source code must retain the above copyright
**     notice, this list of conditions and the following disclaimer.
**   * Redistributions in binary form must reproduce the above copyright
**     notice, this list of conditions and the following disclaimer in
**     the documentation and/or other materials provided with the
**     distribution.
**   * Neither the name of The Qt Company Ltd nor the names of its
**     contributors may be used to endorse or promote products derived
**     from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
** "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
** LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
** A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
** OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
** SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
** LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
** DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
** THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
** OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************/

#ifndef KEEL_BACKEND515_H
#define KEEL_BACKEND515_H

#include <QHash>
#include <QPointer>
#include <QRasterWindow>
#include <QWaylandCompositor>
#include <QWaylandView>

#include "../../core/backend.h"

class QWaylandOutput;
class QWaylandSurface;
class QWaylandWlShell;
class QWaylandWlShellSurface;
class QWaylandXdgPopup;
class QWaylandXdgShell;
class QWaylandXdgSurface;
class QWaylandXdgToplevel;

namespace keel {

class Backend515;

class View515 : public QWaylandView
{
    Q_OBJECT
public:
    View515(QWaylandSurface *surface, QObject *parent);

    SurfaceInfo info() const;
    SurfaceKey key() const { return reinterpret_cast<SurfaceKey>(surface()); }
    bool hasRole() const;

    QPointer<QWaylandWlShellSurface> wlShellSurface;
    QPointer<QWaylandXdgToplevel> xdgToplevel;
    QPointer<QWaylandXdgPopup> xdgPopup;
    QPointer<View515> parentView;
    SurfaceKind kind = SurfaceKind::Unknown;
    QPointF relativePosition;   // relative to parent view
    bool mapped = false;

    QPointF position() const;   // in outer-window coordinates
    void sendConfigure(const QSize &size) const;
    void sendClose() const;
};

class OuterWindow515 : public QRasterWindow
{
    Q_OBJECT
public:
    OuterWindow515(Backend515 *backend, int windowId);

    int windowId() const { return m_windowId; }
    QWaylandOutput *output() const { return m_output; }
    void setOutput(QWaylandOutput *output) { m_output = output; }

    void addView(View515 *view);
    void removeView(View515 *view);
    QList<View515 *> views() const;
    View515 *primaryView() const;

protected:
    void paintEvent(QPaintEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void mousePressEvent(QMouseEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;
    void mouseMoveEvent(QMouseEvent *e) override;
    void keyPressEvent(QKeyEvent *e) override;
    void keyReleaseEvent(QKeyEvent *e) override;
    void touchEvent(QTouchEvent *e) override;

private:
    View515 *viewAt(const QPointF &point) const;
    void updateOutputMode();

    Backend515 *m_backend;
    int m_windowId;
    QWaylandOutput *m_output = nullptr;
    QList<QPointer<View515>> m_views;
    QPointer<View515> m_mouseView;
};

class Backend515 : public Backend
{
    Q_OBJECT
public:
    explicit Backend515(ShellState *state, QObject *parent = nullptr);
    ~Backend515() override;

    bool start(const BackendConfig &config) override;
    QString socketName() const override;
    QString name() const override { return QStringLiteral("qt515"); }

    QWaylandCompositor *compositor() { return &m_compositor; }
    void setFocusSurface(QWaylandSurface *surface);
    int keyboardHeight() const { return m_keyboardHeight; }

protected:
    void outerWindowActivated(int windowId) override;

private slots:
    void onSurfaceCreated(QWaylandSurface *surface);
    void onSubsurfaceChanged(QWaylandSurface *child, QWaylandSurface *parent);
    void onWlShellSurfaceCreated(QWaylandWlShellSurface *shellSurface);
    void onXdgToplevelCreated(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface);
    void onXdgPopupCreated(QWaylandXdgPopup *popup, QWaylandXdgSurface *xdgSurface);

    void onWindowCreated(int windowId, keel::WindowRole role);
    void onWindowDestroyed(int windowId);
    void onSurfaceAssigned(keel::SurfaceKey key, int windowId);
    void onSurfaceRemoved(keel::SurfaceKey key, int windowId);
    void onKeyboardRectChanged();

private:
    View515 *viewFor(QWaylandSurface *surface) const;
    View515 *viewForKey(SurfaceKey key) const;
    void surfaceStateChanged(View515 *view);
    OuterWindow515 *createOuterWindow(int windowId, WindowRole role);
    void configurePrimary(int windowId);

    QWaylandCompositor m_compositor;
    QWaylandWlShell *m_wlShell = nullptr;
    QWaylandXdgShell *m_xdgShell = nullptr;
    QHash<SurfaceKey, QPointer<View515>> m_views;
    QHash<int, OuterWindow515 *> m_windows;
    int m_keyboardHeight = 0;
};

} // namespace keel

#endif // KEEL_BACKEND515_H
