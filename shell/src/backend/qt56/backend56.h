/****************************************************************************
**
** SPDX-FileCopyrightText: 2012 Digia Plc and/or its subsidiary(-ies).
** SPDX-FileCopyrightText: 2017-2020 Elros https://github.com/elros34
** SPDX-FileCopyrightText: 2020-2023 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Sailfish backend of keel-shell: system Qt 5.6.3, QtCompositor (the
** pre-1.0 QtWayland compositor API that Lipstick itself uses).
** Derived from qt-runner src/qmlcompositor.{h,cpp} (BSD-3-Clause, based on
** the QtWayland 5.4 qml-compositor example and qxcompositor). Modified for
** Shipwright: one QQuickWindow and one QWaylandQuickOutput per Lipstick
** window (newcompositor-style multi-window), placement delegated to
** keel::WindowMapper, cover window tagged CATEGORY=cover, no QML/Silica UI.
** Uses QtCompositor private API (QtWayland::Surface::addToOutput /
** removeFromOutput, QtWayland::Surface::subSurface) to move a surface to the
** output of the window it is shown in. See PROVENANCE.md.
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
**   * Neither the name of the copyright holder nor the names of its
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

#ifndef KEEL_BACKEND56_H
#define KEEL_BACKEND56_H

#include <QHash>
#include <QPointer>
#include <QQuickWindow>
#include <QtCompositor/QWaylandQuickCompositor>

#include "../../core/backend.h"

class QWaylandOutput;
class QWaylandSurface;
class QWaylandSurfaceItem;

namespace keel {

class Backend56;

class Compositor56 : public QObject, public QWaylandQuickCompositor
{
    Q_OBJECT
public:
    Compositor56(Backend56 *backend, const QByteArray &socketName);

    // createOutput() is protected in the 5.6 API.
    QWaylandOutput *addOutput(QQuickWindow *window);

protected:
    void surfaceCreated(QWaylandSurface *surface) Q_DECL_OVERRIDE;

private:
    Backend56 *m_backend;
};

class OuterWindow56 : public QQuickWindow
{
    Q_OBJECT
public:
    OuterWindow56(Backend56 *backend, int windowId, WindowRole role);

    int windowId() const { return m_windowId; }
    WindowRole role() const { return m_role; }
    QWaylandOutput *output() const { return m_output; }
    void setOutput(QWaylandOutput *output) { m_output = output; }

    void layoutItems();

protected:
    void resizeEvent(QResizeEvent *event) Q_DECL_OVERRIDE;

private:
    Backend56 *m_backend;
    int m_windowId;
    WindowRole m_role;
    QWaylandOutput *m_output = nullptr;
};

class Backend56 : public Backend
{
    Q_OBJECT
public:
    explicit Backend56(ShellState *state, QObject *parent = nullptr);
    ~Backend56() Q_DECL_OVERRIDE;

    bool start(const BackendConfig &config) Q_DECL_OVERRIDE;
    QString socketName() const Q_DECL_OVERRIDE { return m_socketName; }
    QString name() const Q_DECL_OVERRIDE { return QStringLiteral("qt56"); }

    int keyboardHeight() const { return m_keyboardHeight; }
    QWaylandSurfaceItem *itemFor(QWaylandSurface *surface) const;
    QWaylandSurface *surfaceForKey(SurfaceKey key) const;

    void onSurfaceCreated(QWaylandSurface *surface);

protected:
    void outerWindowActivated(int windowId) Q_DECL_OVERRIDE;

private slots:
    void onWindowCreated(int windowId, keel::WindowRole role);
    void onWindowDestroyed(int windowId);
    void onSurfaceAssigned(keel::SurfaceKey surface, int windowId);
    void onSurfaceRemoved(keel::SurfaceKey surface, int windowId);
    void onKeyboardRectChanged();

private:
    SurfaceInfo infoFor(QWaylandSurface *surface) const;
    bool isPlaceable(QWaylandSurface *surface) const;
    void surfaceStateChanged(QWaylandSurface *surface);
    OuterWindow56 *createOuterWindow(int windowId, WindowRole role);
    void watchSceneGraph(OuterWindow56 *window);
    void moveToOutput(QWaylandSurface *surface, QWaylandOutput *output);
    void sendFrameCallbacks(int windowId);

    Compositor56 *m_compositor = nullptr;
    QString m_socketName;
    QHash<SurfaceKey, QPointer<QWaylandSurface>> m_surfaces;
    QHash<SurfaceKey, bool> m_mapped;
    QHash<int, OuterWindow56 *> m_windows;
    int m_keyboardHeight = 0;
};

} // namespace keel

#endif // KEEL_BACKEND56_H
