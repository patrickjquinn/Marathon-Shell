// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The phone shell as Keel's QML sees it, exposed as the `Keel.Shell`
// singleton. Two ways to be on a phone (ADR-0016):
//
// * Direct mode (the default on Sailfish; KEEL_DIRECT=1, set by Keel's
//   launcher, keel/sailfishapp keellauncher.cpp): the app's own windows are
//   Lipstick windows (Qt 6 wl-shell + qt_extended_surface, as native Qt 5
//   apps, through keel-wl-shell). The cover window gets the window property
//   CATEGORY=cover before it is first shown; every window gets WINID, and
//   the app's windows BACKGROUND_VISIBLE (Lipstick draws the ambience behind
//   them) and the link to the cover (SAILFISH_HAVE_COVER,
//   SAILFISH_COVER_WINDOW "__winref:<cover WINID>"), as Silica's Qt 5
//   windows do; device orientation is the screen orientation (the
//   wl_output transform Lipstick sets); content orientation is reported with
//   QWindow::reportContentOrientationChange (wl_surface.set_buffer_transform);
//   activation is the application state (keyboard focus); close requests are
//   the main window's close event and SIGTERM; the cover status follows the
//   cover window's visibility and exposure; the ambience is read from dconf
//   (dconfambience.h).
// * keel-shell (KEEL_SHELL=1), the opt-in fallback: the client side of the
//   keel-shell contract (keel/shell/PROTOCOL.md).
//
// keel-shell launches the Qt6 app with:
//   KEEL_SHELL=1, KEEL_SHELL_PROTOCOL=1
//   KEEL_SHELL_DBUS=<peer-to-peer D-Bus address>
//   KEEL_SHELL_COVER_TITLE=<cover window title marker, default "keel:cover">
//   KEEL_SHELL_COVER_ENABLED=0|1, KEEL_SHELL_DPI=<dpi>
// and serves /org/shipwright/keel/Shell, interface org.shipwright.keel.Shell1,
// on that peer connection. This class connects to it, mirrors its properties
// and forwards its signals. Without keel-shell (desktop runs, tests) it stays
// disconnected and reports defaults.
//
// Thin C++ by design: QtDBus is the natural binding for a QObject whose
// properties QML binds to; the plan's Rust policy covers logic, and there is
// none here beyond marshalling.
#ifndef KEEL_SHELLCLIENT_H
#define KEEL_SHELLCLIENT_H

#include <QDBusConnection>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantMap>

class QScreen;
class QWindow;

namespace keel {

class ShellClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool underShell READ underShell CONSTANT)
    Q_PROPERTY(bool direct READ direct CONSTANT)
    // On a phone: under keel-shell or in direct mode.
    Q_PROPERTY(bool phone READ phone CONSTANT)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(int protocolVersion READ protocolVersion NOTIFY protocolVersionChanged)
    Q_PROPERTY(int orientation READ orientation NOTIFY orientationChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int coverStatus READ coverStatus NOTIFY coverStatusChanged)
    Q_PROPERTY(int dpi READ dpi NOTIFY dpiChanged)
    Q_PROPERTY(QString coverTitle READ coverTitle CONSTANT)
    Q_PROPERTY(bool coverEnabled READ coverEnabled CONSTANT)
    Q_PROPERTY(QVariantMap ambience READ ambience NOTIFY ambienceChanged)

public:
    // keel-shell's CoverStatus property values (PROTOCOL.md: 0 inactive,
    // 1 active). Cover.status maps them to Cover.Inactive / Cover.Active.
    enum CoverStatus { CoverInactive = 0, CoverActive = 1 };
    Q_ENUM(CoverStatus)

    explicit ShellClient(QObject *parent = nullptr);
    ~ShellClient() override;

    // Process-wide instance; QML engines share it (CppOwnership).
    static ShellClient *instance();

    bool underShell() const { return m_underShell; }
    bool direct() const { return m_direct; }
    bool phone() const { return m_underShell || m_direct; }
    bool connected() const { return m_connected; }
    int protocolVersion() const { return m_protocolVersion; }
    int orientation() const { return m_orientation; }
    bool active() const { return m_active; }
    int coverStatus() const { return m_coverStatus; }
    int dpi() const { return m_dpi; }
    QString coverTitle() const { return m_coverTitle; }
    bool coverEnabled() const { return m_coverEnabled; }
    QVariantMap ambience() const { return m_ambience; }

    // Connects to `address` (normally KEEL_SHELL_DBUS). Public for tests.
    Q_INVOKABLE bool connectTo(const QString &address);

    // Asks keel-shell to raise the app (ApplicationWindow.activate()).
    Q_INVOKABLE void activate();
    // Tells the shell the orientation the UI is laid out in, in degrees.
    Q_INVOKABLE void setContentOrientation(int degrees);
    // Direct mode: makes `window` (a QWindow, not yet shown) the Lipstick
    // cover: creates its platform window and sets CATEGORY=cover, which Qt's
    // wl-shell integration sends before the first buffer. No-op otherwise.
    Q_INVOKABLE void prepareCoverWindow(QObject *object);
    // Direct mode: a Lipstick window property on `object` (a QWindow), for
    // QML (the cover's TRANSPARENT). No-op otherwise.
    Q_INVOKABLE void setLipstickProperty(QObject *object, const QString &name, const QVariant &value) const;

    // Window property through Qt's platform native interface (Qt Wayland:
    // qt_extended_surface.update_generic_property). False without a
    // platform window or without the private Qt GUI headers at build time.
    static bool setWindowProperty(QWindow *window, const QString &name, const QVariant &value);

    // Serialises an ambience map as "key=value" lines for Keel.Ambience.
    static QString ambienceLines(const QVariantMap &ambience);

signals:
    void connectedChanged();
    void protocolVersionChanged();
    void orientationChanged();
    void activeChanged();
    void coverStatusChanged();
    void dpiChanged();
    void ambienceChanged();
    void closeRequested();

private slots:
    void onOrientationChanged(int degrees);
    void onActiveChanged(bool active);
    void onCoverStatusChanged(int status);
    void onAmbienceChanged(const QVariantMap &ambience);
    void onDpiChanged(int dpi);
    void onCloseRequested();

private:
    void fetchProperties();
    void applyProperties(const QVariantMap &props);

    // Direct mode.
    bool eventFilter(QObject *watched, QEvent *event) override;
    void startDirect();
    void trackScreen(QScreen *screen);
    void updateDirectOrientation();
    void updateDirectActive();
    void updateCoverStatus();
    void applyContentOrientation();
    bool isCoverWindow(const QObject *object) const;
    void tagAppWindow(QWindow *window);
    void linkCover(QWindow *window);
    void installTermHandler();
    void onTermSignal();

    bool m_direct = false;
    bool m_termInstalled = false;
    int m_contentOrientation = 0;
    QPointer<QWindow> m_coverWindow;
    QList<QPointer<QWindow>> m_appWindows;
    QPointer<QScreen> m_screen;
    class DconfAmbience *m_dconf = nullptr;

    QDBusConnection m_bus;
    QString m_connectionName;
    bool m_underShell = false;
    bool m_connected = false;
    int m_protocolVersion = 0;
    int m_orientation = 0;
    bool m_active = true;
    int m_coverStatus = CoverInactive;
    int m_dpi = 0;
    QString m_coverTitle;
    bool m_coverEnabled = false;
    QVariantMap m_ambience;
};

} // namespace keel

#endif // KEEL_SHELLCLIENT_H
