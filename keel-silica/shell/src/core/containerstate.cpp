/****************************************************************************
**
** SPDX-FileCopyrightText: 2020 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2023 Artur Gaspar
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from qt-runner src/dbuscontainerstate.cpp and newcompositor
** src/dbuscontainerstate.cpp. Full BSD-3-Clause text in containerstate.h
** and upstream-licenses/. See PROVENANCE.md.
**
****************************************************************************/

#include "containerstate.h"

#include "orientation.h"
#include "shellstate.h"

namespace keel {

ContainerState::ContainerState(ShellState *state, bool portraitPrimary, QObject *parent)
    : QObject(parent)
    , m_state(state)
    , m_portraitPrimary(portraitPrimary)
{
    connect(m_state, &ShellState::activeChanged, this, &ContainerState::activeStateChanged);
    connect(m_state, &ShellState::contentOrientationChanged,
            this, &ContainerState::onContentOrientationChanged);
}

int ContainerState::activeState() const
{
    return m_state->active() ? 1 : 0;
}

int ContainerState::orientation() const
{
    const Qt::ScreenOrientation primary = m_portraitPrimary ? Qt::PortraitOrientation
                                                            : Qt::LandscapeOrientation;
    return maliitAngle(angleToOrientation(m_state->contentOrientation(), primary),
                       m_portraitPrimary);
}

void ContainerState::keyboardRect(bool active, int x, int y, int width, int height)
{
    m_state->setKeyboardRect(active, QRect(x, y, width, height));
}

void ContainerState::onContentOrientationChanged(int)
{
    emit orientationChanged(orientation());
}

} // namespace keel
