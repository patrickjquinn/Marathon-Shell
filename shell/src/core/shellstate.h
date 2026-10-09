// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// State keel-shell forwards to the nested app. Backends and main.cpp write
// it; ShellService exposes it over the peer D-Bus connection.

#ifndef KEEL_SHELLSTATE_H
#define KEEL_SHELLSTATE_H

#include <QObject>
#include <QRect>
#include <QVariantMap>

namespace keel {

class ShellState : public QObject
{
    Q_OBJECT
public:
    enum CoverStatus { CoverInactive = 0, CoverActive = 1 };

    explicit ShellState(QObject *parent = nullptr);

    // Device orientation as an angle in degrees (0, 90, 180, 270) clockwise
    // from the screen's primary (native) orientation.
    int orientation() const { return m_orientation; }
    // Orientation the app says its content is drawn in, same convention.
    int contentOrientation() const { return m_contentOrientation; }
    bool active() const { return m_active; }
    int coverStatus() const { return m_coverStatus; }
    QVariantMap ambience() const { return m_ambience; }
    int dpi() const { return m_dpi; }
    bool keyboardActive() const { return m_keyboardActive; }
    QRect keyboardRect() const { return m_keyboardRect; }
    // Height the keyboard takes from the app's content, for
    // --follow-keyboard: Maliit reports the rectangle in the screen's
    // native (portrait) coordinates, so with landscape content the
    // keyboard's height is the rectangle's width. 0 while it is hidden.
    int keyboardHeight() const;

    static int normalizeAngle(int degrees);

public slots:
    void setOrientation(int degrees);
    void setContentOrientation(int degrees);
    void setActive(bool active);
    void setCoverStatus(int status);
    void setAmbience(const QVariantMap &ambience);
    void setDpi(int dpi);
    // From the peer bus, so unchecked input: a rectangle with a negative
    // width or height is ignored. Backends also keep the remaining app
    // height at 1 px or more, which bounds a too-large rectangle.
    void setKeyboardRect(bool active, const QRect &rect);

    // Requests from the app, forwarded to the backend.
    void requestActivate() { emit activateRequested(); }
    void requestClose() { emit closeRequested(); }

signals:
    void orientationChanged(int degrees);
    void contentOrientationChanged(int degrees);
    void activeChanged(bool active);
    void coverStatusChanged(int status);
    void ambienceChanged(const QVariantMap &ambience);
    void dpiChanged(int dpi);
    void keyboardRectChanged(bool active, const QRect &rect);

    void activateRequested();
    void closeRequested();

private:
    int m_orientation = 0;
    int m_contentOrientation = 0;
    bool m_active = false;
    int m_coverStatus = CoverInactive;
    QVariantMap m_ambience;
    int m_dpi = 0;
    bool m_keyboardActive = false;
    QRect m_keyboardRect;
};

} // namespace keel

#endif // KEEL_SHELLSTATE_H
