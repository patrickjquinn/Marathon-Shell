// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "shellstate.h"

namespace keel {

ShellState::ShellState(QObject *parent)
    : QObject(parent)
{
}

int ShellState::normalizeAngle(int degrees)
{
    int a = degrees % 360;
    if (a < 0)
        a += 360;
    // Snap to the nearest quarter turn.
    return ((a + 45) / 90 % 4) * 90;
}

void ShellState::setOrientation(int degrees)
{
    const int a = normalizeAngle(degrees);
    if (a == m_orientation)
        return;
    m_orientation = a;
    emit orientationChanged(a);
}

void ShellState::setContentOrientation(int degrees)
{
    const int a = normalizeAngle(degrees);
    if (a == m_contentOrientation)
        return;
    m_contentOrientation = a;
    emit contentOrientationChanged(a);
}

void ShellState::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    emit activeChanged(active);
}

void ShellState::setCoverStatus(int status)
{
    if (status == m_coverStatus)
        return;
    m_coverStatus = status;
    emit coverStatusChanged(status);
}

void ShellState::setAmbience(const QVariantMap &ambience)
{
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit ambienceChanged(ambience);
}

void ShellState::setDpi(int dpi)
{
    if (dpi == m_dpi)
        return;
    m_dpi = dpi;
    emit dpiChanged(dpi);
}

int ShellState::keyboardHeight() const
{
    if (!m_keyboardActive)
        return 0;
    const bool portraitContent = m_contentOrientation % 180 == 0;
    return portraitContent ? m_keyboardRect.height() : m_keyboardRect.width();
}

void ShellState::setKeyboardRect(bool active, const QRect &rect)
{
    if (active && (rect.width() < 0 || rect.height() < 0))
        return;
    const QRect r = active ? rect : QRect();
    if (active == m_keyboardActive && r == m_keyboardRect)
        return;
    m_keyboardActive = active;
    m_keyboardRect = r;
    emit keyboardRectChanged(active, r);
}

} // namespace keel
