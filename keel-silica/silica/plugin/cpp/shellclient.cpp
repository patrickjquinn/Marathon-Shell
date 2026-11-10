// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "shellclient.h"

#include "coveractions.h"
#include "dconfambience.h"

#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QScreen>
#include <QSocketNotifier>
#include <QTimer>
#include <QQuickWindow>
#include <QWindow>

#if defined(KEEL_HAVE_QPA)
#include <qpa/qplatformnativeinterface.h>
#include <qpa/qplatformwindow.h>
#endif

#include <csignal>
#include <memory>
#if defined(KEEL_HAVE_QPA) && defined(KEEL_HAVE_WAYLAND)
#include <cerrno>
#include <poll.h>
#include <wayland-client.h>
#include <QElapsedTimer>
#include <QThread>
#endif
#include <sys/socket.h>
#include <sched.h>
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

namespace {

// Text size settings live beside the ambience's keys; changing them is not
// an ambience change and applies at once, as in Jolla's apps.
bool isAmbienceKey(const QString &key)
{
    return !key.startsWith(QLatin1String("/desktop/jolla/theme/font/"));
}

bool ambienceDiffers(const QVariantMap &a, const QVariantMap &b)
{
    for (auto it = a.constBegin(); it != a.constEnd(); ++it) {
        if (isAmbienceKey(it.key()) && b.value(it.key()) != it.value())
            return true;
    }
    for (auto it = b.constBegin(); it != b.constEnd(); ++it) {
        if (isAmbienceKey(it.key()) && !a.contains(it.key()))
            return true;
    }
    return false;
}

} // namespace

void ShellClient::onAmbienceChanged(const QVariantMap &ambience)
{
    const QVariantMap &current = m_ambiencePending ? m_pendingAmbience : m_ambience;
    if (ambience == current)
        return;
    // A window starts deferring in this signal's handler.
    if (ambienceDiffers(ambience, current))
        emit ambienceAboutToChange();
    if (m_deferAmbience) {
        m_pendingAmbience = ambience;
        m_ambiencePending = true;
        return;
    }
    m_ambiencePending = false;
    m_pendingAmbience.clear();
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit ambienceChanged();
}

void ShellClient::setDeferAmbience(bool defer)
{
    if (defer == m_deferAmbience)
        return;
    m_deferAmbience = defer;
    emit deferAmbienceChanged();
    if (!defer && m_ambiencePending) {
        const QVariantMap pending = m_pendingAmbience;
        m_ambiencePending = false;
        m_pendingAmbience.clear();
        if (pending != m_ambience) {
            m_ambience = pending;
            emit ambienceChanged();
        }
    }
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

namespace {

// The CPUs of the fastest cluster (highest cpuinfo_max_freq), or nothing
// where every CPU is alike or the kernel does not say.
const QList<int> &fastCpus()
{
    static const QList<int> cpus = []() {
        QList<int> best;
        qint64 bestFreq = 0;
        int policies = 0;
        bool alike = true;
        const QDir dir(QStringLiteral("/sys/devices/system/cpu/cpufreq"));
        for (const QString &policy : dir.entryList({QStringLiteral("policy*")}, QDir::Dirs)) {
            QFile freqFile(dir.filePath(policy + QStringLiteral("/cpuinfo_max_freq")));
            QFile cpusFile(dir.filePath(policy + QStringLiteral("/related_cpus")));
            if (!freqFile.open(QIODevice::ReadOnly) || !cpusFile.open(QIODevice::ReadOnly))
                continue;
            const qint64 freq = freqFile.readAll().trimmed().toLongLong();
            QList<int> list;
            for (const QByteArray &cpu : cpusFile.readAll().trimmed().split(' '))
                if (!cpu.isEmpty())
                    list.append(cpu.toInt());
            if (policies++ > 0 && freq != bestFreq)
                alike = false;
            if (freq > bestFreq) {
                bestFreq = freq;
                best = list;
            }
        }
        return (policies > 1 && !alike) ? best : QList<int>();
    }();
    return cpus;
}

// Keeps the threads a frame passes through on the fast cluster: the scene
// graph's render threads and Qt Wayland's event threads (Lipstick's frame
// callback wakes one, which wakes the render thread, which swaps). Opt-in,
// KEEL_FAST_CORES=1. On an Xperia 10 II (Snapdragon 665, schedutil) that
// was charging from flat, when Lipstick ran at about 30 fps, it took the
// share of flick frames longer than two vsyncs from 72% to 53% (Qt 5
// Silica 60%) and p99 from 116 to 59 ms. On the same phone charged, at 60
// fps, and with the clocks capped, it made p99 worse (46 against 34 ms):
// the threads then compete with Lipstick's for the fast cores. Measured on
// 2026-10-18 with a 400-row Silica list and scripted flicks.
void pinFrameThreads()
{
    static const bool enabled = qEnvironmentVariable("KEEL_FAST_CORES") == QStringLiteral("1");
    const QList<int> &cpus = fastCpus();
    if (!enabled || cpus.isEmpty())
        return;
    cpu_set_t set;
    CPU_ZERO(&set);
    for (int cpu : cpus)
        CPU_SET(cpu, &set);
    const QDir tasks(QStringLiteral("/proc/self/task"));
    for (const QString &tid : tasks.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        QFile comm(tasks.filePath(tid + QStringLiteral("/comm")));
        if (!comm.open(QIODevice::ReadOnly))
            continue;
        const QByteArray name = comm.readAll().trimmed();
        if (name == "QSGRenderThread" || name.startsWith("WaylandEventThr"))
            sched_setaffinity(tid.toInt(), sizeof(set), &set);
    }
}

// Once per window, at its first frame (its render thread exists by then).
void pinFrameThreadsOnFirstFrame(QWindow *window)
{
    auto *quick = qobject_cast<QQuickWindow *>(window);
    if (!quick || quick->property("_keelFramePinned").toBool())
        return;
    quick->setProperty("_keelFramePinned", true);
    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection = QObject::connect(quick, &QQuickWindow::frameSwapped, quick, [connection]() {
        QObject::disconnect(*connection);
        pinFrameThreads();
    }, Qt::DirectConnection);
}

} // namespace

void ShellClient::prepareCoverWindow(QObject *object)
{
    auto *window = qobject_cast<QWindow *>(object);
    if (!m_direct || !window)
        return;
    m_coverWindow = window;
    window->setProperty("keelCover", true);
    pinFrameThreadsOnFirstFrame(window);
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
    connect(window, &QWindow::visibleChanged, this, &ShellClient::onWindowVisibleChanged, Qt::UniqueConnection);
    updateCoverStatus();
}

void ShellClient::onWindowVisibleChanged(bool visible)
{
    if (!visible)
        unmapForLipstick(qobject_cast<QWindow *>(sender()));
}

// Qt's Wayland client takes a window down (QWaylandWindow::reset(), on hide
// and on destroy) by destroying its EGL buffers while the last one is still
// attached, and only then the wl_surface. Lipstick (lipstick-qt5 0.37,
// WindowPixmapItem::handleWindowSizeChanged()) gets the size change of the
// lost buffer as a queued call and, about half the time, runs it after the
// surface's window item is gone: a null dereference that restarts the home
// screen and every app with it. So unmap the window first, while it is
// whole: a null buffer and a commit, a roundtrip on a queue of our own (Qt's
// event thread keeps reading the display) so that Lipstick has handled the
// commit, and a moment for Lipstick to deliver what it queued for it. Called
// from visibleChanged(false), which QWindow emits before it touches the
// platform window.
void ShellClient::unmapForLipstick(QWindow *window)
{
#if defined(KEEL_HAVE_QPA) && defined(KEEL_HAVE_WAYLAND)
    static const bool enabled = qgetenv("KEEL_UNMAP_BEFORE_DESTROY") != "0";
    if (!enabled || !window || !window->handle())
        return;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native)
        return;
    auto *surface = static_cast<wl_surface *>(native->nativeResourceForWindow("surface", window));
    auto *display = static_cast<wl_display *>(native->nativeResourceForIntegration("wl_display"));
    if (!surface || !display)
        return;
    wl_surface_attach(surface, nullptr, 0, 0);
    wl_surface_commit(surface);

    wl_event_queue *queue = wl_display_create_queue(display);
    auto *wrapper = static_cast<wl_display *>(wl_proxy_create_wrapper(display));
    wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(wrapper), queue);
    bool done = false;
    static const wl_callback_listener listener = {
        [](void *data, wl_callback *callback, uint32_t) {
            *static_cast<bool *>(data) = true;
            wl_callback_destroy(callback);
        },
    };
    wl_callback *callback = wl_display_sync(wrapper);
    wl_callback_add_listener(callback, &listener, &done);
    wl_proxy_wrapper_destroy(wrapper);

    // At most half a second: a compositor that does not answer must not
    // keep the app from closing.
    QElapsedTimer timer;
    timer.start();
    bool failed = false;
    while (!done && !failed && timer.elapsed() < 500) {
        while (wl_display_prepare_read_queue(display, queue) != 0) {
            if (wl_display_dispatch_queue_pending(display, queue) < 0) {
                failed = true;
                break;
            }
        }
        if (failed || done) {
            if (!failed)
                wl_display_cancel_read(display);
            break;
        }
        if (wl_display_flush(display) < 0 && errno != EAGAIN) {
            wl_display_cancel_read(display);
            break;
        }
        pollfd fd = { wl_display_get_fd(display), POLLIN, 0 };
        const int left = 500 - static_cast<int>(timer.elapsed());
        if (::poll(&fd, 1, left > 0 ? left : 0) > 0) {
            if (wl_display_read_events(display) < 0)
                break;
        } else {
            wl_display_cancel_read(display);
        }
        if (wl_display_dispatch_queue_pending(display, queue) < 0)
            break;
    }
    if (!done) {
        // Destroyed, it cannot fire into `done` later.
        wl_callback_destroy(callback);
        qCWarning(lcKeelShell) << "Lipstick did not answer the unmap of" << window;
    }
    wl_event_queue_destroy(queue);
    // Lipstick has handled the commit; let its event loop deliver what that
    // queued before the surface goes.
    if (done)
        QThread::msleep(50);
#else
    Q_UNUSED(window)
#endif
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
    pinFrameThreadsOnFirstFrame(window);
    if (!m_appWindows.contains(window))
        m_appWindows.append(window);
    connect(window, &QWindow::visibleChanged, this, &ShellClient::onWindowVisibleChanged, Qt::UniqueConnection);
    setWindowProperty(window, QStringLiteral("WINID"), windowLinkId(window));
    setWindowProperty(window, QStringLiteral("BACKGROUND_VISIBLE"), true);
    linkCover(window);
    if (!m_coverActionValue.isEmpty())
        setWindowProperty(window, QStringLiteral("_APP_COVER_ACTION"), m_coverActionValue);
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

void ShellClient::setCoverActions(QObject *object, const QStringList &icons, bool iconBackground)
{
    auto *window = qobject_cast<QWindow *>(object);
    if (!m_direct || !window)
        return;
    // One name for the process's cover window, owned from its first action
    // to the end (Silica keeps its name the same way).
    if (!m_coverActions && !icons.isEmpty()) {
        const QString service = CoverActions::serviceName(QCoreApplication::organizationName(),
                                                          QCoreApplication::applicationName(),
                                                          QCoreApplication::applicationPid(),
                                                          windowLinkId(window));
        m_coverActions = new CoverActions(QDBusConnection::sessionBus(), service, this);
        connect(m_coverActions, &CoverActions::triggered, this, &ShellClient::coverActionTriggered);
    }
    const bool live = m_coverActions && m_coverActions->registered();
    m_coverActionValue = live ? CoverActions::propertyValue(m_coverActions->service(), icons, iconBackground)
                              : QString();
    // Lipstick's switcher reads it from the app's window, not the cover
    // (Silica sets it there too). No actions (a cover's list disabled, as
    // Keys' while it is locked) clear the property: an empty string is an
    // action Lipstick cannot read ("CoverActionModel: Bad action").
    const QVariant value = m_coverActionValue.isEmpty() ? QVariant() : QVariant(m_coverActionValue);
    for (const QPointer<QWindow> &w : std::as_const(m_appWindows)) {
        if (w)
            setWindowProperty(w, QStringLiteral("_APP_COVER_ACTION"), value);
    }
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
