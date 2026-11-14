/****************************************************************************
**
** SPDX-FileCopyrightText: 2020 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2023 Artur Gaspar
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from qt-runner src/dbuscontainerstate.h (BSD-3-Clause) and
** newcompositor src/dbuscontainerstate.h (BSD-3-Clause). Modified for
** Shipwright keel-shell: state comes from keel::ShellState instead of a
** QQuickView. See PROVENANCE.md.
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

#ifndef KEEL_CONTAINERSTATE_H
#define KEEL_CONTAINERSTATE_H

#include <QObject>

// Wire names used by the Qt6 Maliit input context plugin
// (maliit-framework input-context/minputcontext.cpp, sailfishos-flatpak fork).
#define FLATPAK_RUNNER_DBUS_CONT_IFACE "org.container"
#define FLATPAK_RUNNER_DBUS_CONT_SERVICE "org.flatpak.sailfish.container"

namespace keel {

class ShellState;

class ContainerState : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", FLATPAK_RUNNER_DBUS_CONT_IFACE)

    Q_PROPERTY(int activeState READ activeState NOTIFY activeStateChanged)
    Q_PROPERTY(int orientation READ orientation NOTIFY orientationChanged)

public:
    ContainerState(ShellState *state, bool portraitPrimary, QObject *parent = nullptr);

    int activeState() const;
    int orientation() const;

public slots:
    // The one method peers may call (exported as a scriptable slot).
    Q_SCRIPTABLE void keyboardRect(bool active, int x, int y, int width, int height);

signals:
    void activeStateChanged(bool state);
    void orientationChanged(int orientation);

private slots:
    void onContentOrientationChanged(int degrees);

private:
    ShellState *m_state;
    bool m_portraitPrimary;
};

} // namespace keel

#endif // KEEL_CONTAINERSTATE_H
