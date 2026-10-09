// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "shellclient.h"

#include "dconfambience.h"

#include <QDBusPendingCallWatcher>
#include <QGuiApplication>
#include <QScreen>
#include <QSocketNotifier>
#include <QTimer>
#include <QWindow>

#if defined(KEEL_HAVE_QPA)
#include <qpa/qplatformnativeinterface.h>
#include <qpa/qplatformwindow.h>
#endif

#include <csignal>
#include <sys/socket.h>
#include <unistd.h>

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QLoggingCategory>
#include <QtGlobal>

Q_LOGGING_CATEGORY(lcKeelShell, "keel.shell")

namespace keel {

static const char *const kPath = "/org/shipwright/keel/Shell";
static const char *const kIface = "org.shipwright.keel.Shell1";

ShellClient::ShellClient(QObject *parent)
    : QObject(parent)
    , m_bus(QString())
    , m_dpi(qEnvironmentVariableIntValue("KEEL_SHELL_DPI"))
{
    m_underShell = qEnvironmentVariable("KEEL_SHELL") == QLatin1String("1");
    // Direct mode: Keel's launcher sets KEEL_DIRECT=1 on Sailfish
    // (keel/sailfishapp/src/keellauncher.cpp); keel-shell wins if both are set.
    m_direct = !m_underShell && qEnvironmentVariable("KEEL_DIRECT") == QLatin1String("1");
    m_coverTitle = qEnvironmentVariable("KEEL_SHELL_COVER_TITLE", QStringLiteral("keel:cover"));
    m_coverEnabled = m_underShell ? qEnvironmentVariable("KEEL_SHELL_COVER_ENABLED") != QLatin1String("0")
                                  : m_direct && qEnvironmentVariable("KEEL_COVER") != QLatin1String("0");
    const QString address = qEnvironmentVariable("KEEL_SHELL_DBUS");
    if (m_underShell && !address.isEmpty())
        connectTo(address);
    if (m_direct)
        startDirect();
}

ShellClient::~ShellClient()
{
    if (!m_connectionName.isEmpty())
        QDBusConnection::disconnectFromPeer(m_connectionName);
}

ShellClient *ShellClient::instance()
{
    static auto *s = new ShellClient;
    return s;
}

bool ShellClient::connectTo(const QString &address)
{
    if (m_connected)
        return true;
    static int counter = 0;
    m_connectionName = QStringLiteral("keel-shell-%1").arg(++counter);
    m_bus = QDBusConnection::connectToPeer(address, m_connectionName);
    if (!m_bus.isConnected()) {
        qCWarning(lcKeelShell) << "cannot connect to keel-shell at" << address << m_bus.lastError().message();
        return false;
    }
    const QString path = QLatin1String(kPath);
    const QString iface = QLatin1String(kIface);
    m_bus.connect(QString(), path, iface, QStringLiteral("OrientationChanged"), this, SLOT(onOrientationChanged(int)));
    m_bus.connect(QString(), path, iface, QStringLiteral("ActiveChanged"), this, SLOT(onActiveChanged(bool)));
    m_bus.connect(QString(), path, iface, QStringLiteral("CoverStatusChanged"), this, SLOT(onCoverStatusChanged(int)));
    m_bus.connect(QString(), path, iface, QStringLiteral("AmbienceChanged"), this, SLOT(onAmbienceChanged(QVariantMap)));
    m_bus.connect(QString(), path, iface, QStringLiteral("DpiChanged"), this, SLOT(onDpiChanged(int)));
    m_bus.connect(QString(), path, iface, QStringLiteral("CloseRequested"), this, SLOT(onCloseRequested()));
    m_connected = true;
    fetchProperties();
    emit connectedChanged();
    return true;
}

static QVariant unwrap(const QVariant &v)
{
    if (v.canConvert<QDBusVariant>())
        return v.value<QDBusVariant>().variant();
    return v;
}

static QVariantMap toMap(const QVariant &v)
{
    const QVariant u = unwrap(v);
    if (u.userType() == qMetaTypeId<QDBusArgument>()) {
        QVariantMap map;
        u.value<QDBusArgument>() >> map;
        return map;
    }
    return u.toMap();
}

// Asynchronous, so that a busy keel-shell never blocks the app's start-up;
// the defaults are reported until the reply arrives, and the signals
// connected in connectTo() keep the values current afterwards.
void ShellClient::fetchProperties()
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QString(), QLatin1String(kPath),
                                                      QStringLiteral("org.freedesktop.DBus.Properties"),
                                                      QStringLiteral("GetAll"));
    msg << QLatin1String(kIface);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, 2000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
            qCWarning(lcKeelShell) << "keel-shell GetAll failed:" << reply.errorMessage();
            return;
        }
        applyProperties(toMap(reply.arguments().constFirst()));
    });
}

void ShellClient::applyProperties(const QVariantMap &props)
{
    const int version = unwrap(props.value(QStringLiteral("ProtocolVersion"))).toInt();
    if (version != m_protocolVersion) {
        m_protocolVersion = version;
        emit protocolVersionChanged();
    }
    if (props.contains(QStringLiteral("Orientation")))
        onOrientationChanged(unwrap(props.value(QStringLiteral("Orientation"))).toInt());
    if (props.contains(QStringLiteral("Active")))
        onActiveChanged(unwrap(props.value(QStringLiteral("Active"))).toBool());
    if (props.contains(QStringLiteral("CoverStatus")))
        onCoverStatusChanged(unwrap(props.value(QStringLiteral("CoverStatus"))).toInt());
    if (props.contains(QStringLiteral("Dpi")))
        onDpiChanged(unwrap(props.value(QStringLiteral("Dpi"))).toInt());
    if (props.contains(QStringLiteral("Ambience")))
        onAmbienceChanged(toMap(props.value(QStringLiteral("Ambience"))));
}

void ShellClient::activate()
{
    if (m_direct) {
        // qt_extended_surface.raise plus activation; Lipstick decides.
        const QWindowList windows = QGuiApplication::topLevelWindows();
        for (QWindow *w : windows) {
            if (!isCoverWindow(w) && w->isVisible()) {
                w->raise();
                w->requestActivate();
                break;
            }
        }
        return;
    }
    if (!m_connected)
        return;
    m_bus.asyncCall(QDBusMessage::createMethodCall(QString(), QLatin1String(kPath),
                                                   QLatin1String(kIface), QStringLiteral("Activate")));
}

void ShellClient::setContentOrientation(int degrees)
{
    if (m_direct) {
        m_contentOrientation = ((degrees % 360) + 360) % 360;
        applyContentOrientation();
        return;
    }
    if (!m_connected)
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(QString(), QLatin1String(kPath), QLatin1String(kIface),
                                                      QStringLiteral("SetContentOrientation"));
    msg << degrees;
    m_bus.asyncCall(msg);
}

QString ShellClient::ambienceLines(const QVariantMap &ambience)
{
    QString out;
    for (auto it = ambience.constBegin(); it != ambience.constEnd(); ++it) {
        const QVariant v = unwrap(it.value());
        QString text = v.userType() == QMetaType::Bool ? (v.toBool() ? QStringLiteral("true")
                                                                      : QStringLiteral("false"))
                                                        : v.toString();
        text.replace(QLatin1Char('\n'), QLatin1Char(' '));
        out += it.key() + QLatin1Char('=') + text + QLatin1Char('\n');
    }
    return out;
}

void ShellClient::onOrientationChanged(int degrees)
{
    degrees = ((degrees % 360) + 360) % 360;
    if (degrees == m_orientation)
        return;
    m_orientation = degrees;
    emit orientationChanged();
}

void ShellClient::onActiveChanged(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    emit activeChanged();
}

void ShellClient::onCoverStatusChanged(int status)
{
    if (status == m_coverStatus)
        return;
    m_coverStatus = status;
    emit coverStatusChanged();
}

void ShellClient::onAmbienceChanged(const QVariantMap &ambience)
{
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit ambienceChanged();
}

void ShellClient::onDpiChanged(int dpi)
{
    if (dpi == m_dpi)
        return;
    m_dpi = dpi;
    emit dpiChanged();
}

void ShellClient::onCloseRequested()
{
    emit closeRequested();
}

// --- Direct mode ---------------------------------------------------------------

bool ShellClient::setWindowProperty(QWindow *window, const QString &name, const QVariant &value)
{
#if defined(KEEL_HAVE_QPA)
    if (!window || !window->handle())
        return false;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native)
        return false;
    native->setWindowProperty(window->handle(), name, value);
    return true;
#else
    Q_UNUSED(window)
    Q_UNUSED(name)
    Q_UNUSED(value)
    return false;
#endif
}

// The window's WINID: a number unique in the process, the same for the
// window's life (Lipstick matches it with the process id).
static uint windowLinkId(QWindow *window)
{
    static uint next = 0;
    QVariant id = window->property("keelWinId");
    if (!id.isValid()) {
        id = ++next;
        window->setProperty("keelWinId", id);
    }
    return id.toUInt();
}

void ShellClient::prepareCoverWindow(QObject *object)
{
    auto *window = qobject_cast<QWindow *>(object);
    if (!m_direct || !window)
        return;
    m_coverWindow = window;
    window->setProperty("keelCover", true);
    // The platform window must exist for the property; Qt's Wayland client
    // keeps it and sends it when the shell surface is created on show(),
    // before the first commit. Lipstick reads CATEGORY when the window is
    // first mapped (lipstickcompositor.cpp, createView()).
    window->create();
    if (!setWindowProperty(window, QStringLiteral("CATEGORY"), QStringLiteral("cover")))
        qCWarning(lcKeelShell) << "cannot tag the cover window CATEGORY=cover (no platform window or no QPA)";
    setWindowProperty(window, QStringLiteral("WINID"), windowLinkId(window));
    for (const QPointer<QWindow> &w : std::as_const(m_appWindows)) {
        if (w)
            linkCover(w);
    }
    connect(window, &QWindow::visibilityChanged, this, &ShellClient::updateCoverStatus);
    connect(window, &QWindow::visibleChanged, this, &ShellClient::updateCoverStatus);
    updateCoverStatus();
}

void ShellClient::setLipstickProperty(QObject *object, const QString &name, const QVariant &value) const
{
    auto *window = qobject_cast<QWindow *>(object);
    if (m_direct && window)
        setWindowProperty(window, name, value);
}

// What Silica's Qt 5 window (Sailfish.Silica.private Window) tells Lipstick
// about an app window (lipstick-jolla-home: WindowWrapper.qml, Switcher.qml;
// lipstick: windowproperty.cpp). Without BACKGROUND_VISIBLE Lipstick draws
// nothing behind the translucent window and the home screen shows through.
void ShellClient::tagAppWindow(QWindow *window)
{
    if (!m_appWindows.contains(window))
        m_appWindows.append(window);
    setWindowProperty(window, QStringLiteral("WINID"), windowLinkId(window));
    setWindowProperty(window, QStringLiteral("BACKGROUND_VISIBLE"), true);
    linkCover(window);
}

void ShellClient::linkCover(QWindow *window)
{
    QWindow *cover = m_coverWindow.data();
    if (!cover || !cover->handle())
        return;
    // Lipstick resolves "__winref:<n>" to the window of the same process
    // whose WINID is n (LipstickCompositor::windowIdForLink()).
    setWindowProperty(window, QStringLiteral("SAILFISH_HAVE_COVER"), true);
    setWindowProperty(window, QStringLiteral("SAILFISH_COVER_WINDOW"),
                      QStringLiteral("__winref:%1").arg(windowLinkId(cover)));
}

bool ShellClient::isCoverWindow(const QObject *object) const
{
    return object && (object == m_coverWindow.data() || object->property("keelCover").toBool());
}

void ShellClient::startDirect()
{
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (!app)
        return;
    app->installEventFilter(this);
    connect(app, &QGuiApplication::applicationStateChanged, this, &ShellClient::updateDirectActive);
    connect(app, &QGuiApplication::primaryScreenChanged, this, &ShellClient::trackScreen);
    connect(app, &QGuiApplication::focusWindowChanged, this, &ShellClient::applyContentOrientation);
    trackScreen(QGuiApplication::primaryScreen());
    m_active = QGuiApplication::applicationState() == Qt::ApplicationActive;

    m_dconf = new DconfAmbience(this);
    if (m_dconf->available()) {
        m_dconf->readNow();
        m_ambience = m_dconf->values();
        connect(m_dconf, &DconfAmbience::changed, this, &ShellClient::onAmbienceChanged);
        m_dconf->startWatching();
    }
}

void ShellClient::trackScreen(QScreen *screen)
{
    if (!screen || screen == m_screen)
        return;
    if (m_screen)
        disconnect(m_screen.data(), nullptr, this, nullptr);
    m_screen = screen;
    connect(screen, &QScreen::orientationChanged, this, &ShellClient::updateDirectOrientation);
    connect(screen, &QScreen::primaryOrientationChanged, this, &ShellClient::updateDirectOrientation);
    updateDirectOrientation();
}

// Direct mode's degrees are absolute, as Silica's Orientation values and
// ApplicationWindow's _fromDegrees()/_degrees(): 0 portrait, 90 landscape,
// 180 inverted portrait, 270 inverted landscape.
static int directDegrees(Qt::ScreenOrientation o)
{
    switch (o) {
    case Qt::LandscapeOrientation: return 90;
    case Qt::InvertedPortraitOrientation: return 180;
    case Qt::InvertedLandscapeOrientation: return 270;
    default: return 0;
    }
}

void ShellClient::updateDirectOrientation()
{
    if (!m_screen)
        return;
    // Lipstick turns the output (wl_output transform) when the device turns
    // (QWaylandCompositor::setScreenOrientation); Qt's Wayland client
    // reports it as the screen orientation (QWaylandScreen, same table in
    // Qt 5.6 and Qt 6).
    Qt::ScreenOrientation o = m_screen->orientation();
    if (o == Qt::PrimaryOrientation)
        o = m_screen->primaryOrientation();
    onOrientationChanged(directDegrees(o));
}

void ShellClient::updateDirectActive()
{
    onActiveChanged(QGuiApplication::applicationState() == Qt::ApplicationActive);
    updateCoverStatus();
}

void ShellClient::updateCoverStatus()
{
    if (!m_direct)
        return;
    QWindow *cover = m_coverWindow.data();
    // Lipstick shows the cover while the app is in the background: the app
    // has lost activation and the cover window is mapped, exposed and not
    // hidden or minimised through qt_extended_surface.onscreen_visibility.
    const bool shown = cover && cover->isVisible() && cover->isExposed()
            && cover->visibility() != QWindow::Hidden && cover->visibility() != QWindow::Minimized;
    onCoverStatusChanged(shown && !m_active ? CoverActive : CoverInactive);
}

void ShellClient::applyContentOrientation()
{
    if (!m_direct)
        return;
    static const Qt::ScreenOrientation byDegrees[] = { Qt::PortraitOrientation, Qt::LandscapeOrientation,
                                                       Qt::InvertedPortraitOrientation,
                                                       Qt::InvertedLandscapeOrientation };
    const Qt::ScreenOrientation o = byDegrees[(m_contentOrientation / 90) % 4];
    const QWindowList windows = QGuiApplication::topLevelWindows();
    for (QWindow *w : windows) {
        // Covers are drawn by Lipstick in its own orientation.
        if (!isCoverWindow(w) && w->contentOrientation() != o)
            w->reportContentOrientationChange(o);
    }
}

namespace {
int g_termFds[2] = { -1, -1 };

void onTerm(int)
{
    const char c = 1;
    const ssize_t ignored = ::write(g_termFds[0], &c, 1);
    Q_UNUSED(ignored)
}
} // namespace

void ShellClient::installTermHandler()
{
    // Lipstick ends an app with SIGTERM (LipstickCompositorWindow::
    // terminateProcess) and SIGKILL after a timeout. Give the app the same
    // CloseRequested chance keel-shell gave it. Installed when the first
    // app window is shown, so a booster's preloaded instance never has it
    // (mapplauncherd resets signal handlers before it calls the app's main).
    if (m_termInstalled || ::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, g_termFds) != 0)
        return;
    m_termInstalled = true;
    auto *notifier = new QSocketNotifier(g_termFds[1], QSocketNotifier::Read, this);
    connect(notifier, &QSocketNotifier::activated, this, &ShellClient::onTermSignal);
    struct sigaction sa {};
    sa.sa_handler = onTerm;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    ::sigaction(SIGTERM, &sa, nullptr);
}

void ShellClient::onTermSignal()
{
    char c = 0;
    const ssize_t ignored = ::read(g_termFds[1], &c, 1);
    Q_UNUSED(ignored)
    qCInfo(lcKeelShell) << "SIGTERM: close requested";
    emit closeRequested();
    // As keel-shell's grace period: quit even if the app does not.
    QTimer::singleShot(3000, QCoreApplication::instance(), []() { QCoreApplication::exit(0); });
}

bool ShellClient::eventFilter(QObject *watched, QEvent *event)
{
    switch (event->type()) {
    case QEvent::Show:
        if (auto *w = qobject_cast<QWindow *>(watched); w && !isCoverWindow(w) && !w->transientParent()) {
            installTermHandler();
            tagAppWindow(w);
            if (m_contentOrientation != 0)
                applyContentOrientation();
        }
        break;
    case QEvent::Expose:
        if (isCoverWindow(watched))
            QMetaObject::invokeMethod(this, &ShellClient::updateCoverStatus, Qt::QueuedConnection);
        break;
    case QEvent::Close:
        // Lipstick's close (qt_extended_surface.close) on an app window:
        // keep the window, let the app save and quit (ApplicationWindow
        // quits on closeRequested).
        if (auto *w = qobject_cast<QWindow *>(watched); w && w->isTopLevel() && !isCoverWindow(w)
                && w->isVisible()) {
            event->ignore();
            emit closeRequested();
            return true;
        }
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

} // namespace keel
