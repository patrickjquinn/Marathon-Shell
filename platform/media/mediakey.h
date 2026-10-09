// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MediaKey, Keel's clean-room implementation.
//
// Public API (sailfishos.org/develop/docs/sailfish-media/
// qml-sailfish-media-mediakey.html): `enabled`, `key`, `pressed`; "when
// enabled, MediaKey globally filters key events". The `pressed()`,
// `released()` and `repeat()` signals are the handlers apps use with it
// (onPressed, onReleased, onRepeat in the corpus: foilauth, yubikey,
// hutspot).
//
// How it reaches the keys (PROVENANCE.md, "Sailfish.Media"):
//   1. Lipstick sends a key to a window that is not focused only if the
//      window lists the key in its GRABBED_KEYS window property, a
//      QStringList of decimal Qt key codes (lipstick
//      src/compositor/lipstickcompositorwindow.cpp, refreshGrabbedKeys()).
//      MediaKeyRegistry keeps that property on every top-level window of the
//      app, through QPlatformNativeInterface::setWindowProperty() (the
//      qt_extended_surface generic property on Wayland), and as a QWindow
//      dynamic property of the same name.
//   2. Within the app, an application-wide event filter takes the key
//      events of enabled MediaKeys before any item sees them.
// Lipstick forwards presses and releases only, not auto-repeats; repeats
// come from the client side (the Wayland keyboard's repeat).
#ifndef KEEL_MEDIAKEY_H
#define KEEL_MEDIAKEY_H

#include <QList>
#include <QObject>
#include <QPointer>
#include <QQmlParserStatus>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class QWindow;

class MediaKey : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(bool pressed READ isPressed NOTIFY pressedChanged)
    QML_ELEMENT

public:
    explicit MediaKey(QObject *parent = nullptr);
    ~MediaKey() override;

    bool isEnabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    int key() const { return m_key; }
    void setKey(int key);
    bool isPressed() const { return m_pressed; }

    // Whether this MediaKey takes `key` now.
    bool grabs(int key) const { return m_complete && m_enabled && m_key != 0 && m_key == key; }

    // Called by the registry for a key event of this key.
    void handlePress(bool autoRepeat);
    void handleRelease();

    void classBegin() override { }
    void componentComplete() override;

signals:
    void enabledChanged();
    void keyChanged();
    void pressedChanged();
    // NOLINTBEGIN(readability-redundant-access-specifiers): QML signal API
    void pressed();
    void released();
    void repeat();
    // NOLINTEND(readability-redundant-access-specifiers)

private:
    void setPressed(bool pressed);

    bool m_enabled = true;
    bool m_complete = false;
    bool m_pressed = false;
    int m_key = 0;
};

// One application-wide filter for all MediaKeys, and the GRABBED_KEYS
// window property. Internal; tests use grabbedKeys().
class MediaKeyRegistry : public QObject
{
    Q_OBJECT
public:
    static MediaKeyRegistry *instance();

    void add(MediaKey *key);
    void remove(MediaKey *key);
    // Recomputes the grabbed key set after a MediaKey changed.
    void update();

    // The GRABBED_KEYS value: sorted decimal Qt key codes.
    QStringList grabbedKeys() const { return m_grabbed; }

    static const char *propertyName() { return "GRABBED_KEYS"; }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    MediaKeyRegistry();
    void applyTo(QWindow *window) const;
    void applyToAll() const;

    QList<QPointer<MediaKey>> m_keys;
    QStringList m_grabbed;
    bool m_filtering = false;
};

#endif // KEEL_MEDIAKEY_H
