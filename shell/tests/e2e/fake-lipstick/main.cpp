// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// fake-lipstick: a headless Qt 5.15 Wayland compositor that stands in for
// Lipstick in the end-to-end test. It offers wl_shell, xdg_shell and the
// qt_surface_extension / qt_extended_surface protocol that Lipstick uses to
// receive window properties, decodes update_generic_property exactly as
// QtCompositor does (QDataStream of a QVariant) and writes a JSON report of
// every surface: title, class, properties (CATEGORY!), content and size.
//
// It verifies the wire path keel-shell relies on: QWindow ->
// QPlatformNativeInterface::setWindowProperty -> Qt5 Wayland client ->
// qt_extended_surface.update_generic_property. It does not verify what
// Lipstick does with CATEGORY=cover; that needs a device.

#include <QDataStream>
#include <QGuiApplication>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QSaveFile>
#include <QTimer>
#include <QWaylandCompositor>
#include <QWaylandOutput>
#include <QWaylandOutputMode>
#include <QWaylandSurface>
#include <QWaylandView>
#include <QWaylandWlShell>
#include <QWaylandWlShellSurface>
#include <QWaylandXdgShell>
#include <QWindow>

#include <iostream>
#include <utility>
#include <wayland-server.h>

#include "surface-extension-server-protocol.h"

namespace {

struct SurfaceRecord {
    QPointer<QWaylandSurface> surface;
    QWaylandView *view = nullptr;
    QString title;
    QString className;
    QString role;
    QVariantMap properties;
    int extendedSurfaces = 0;
};

class FakeLipstick : public QObject
{
public:
    FakeLipstick(QString reportPath)
        : m_reportPath(std::move(reportPath))
    {
    }

    QWaylandCompositor compositor;
    QWaylandOutput *output = nullptr;
    QHash<QWaylandSurface *, SurfaceRecord> records;

    void writeReport()
    {
        QJsonArray surfaces;
        for (auto it = records.constBegin(); it != records.constEnd(); ++it) {
            const SurfaceRecord &r = it.value();
            if (!r.surface)
                continue;
            QJsonObject o;
            o.insert(QStringLiteral("title"), r.title);
            o.insert(QStringLiteral("class"), r.className);
            o.insert(QStringLiteral("role"), r.role);
            o.insert(QStringLiteral("hasContent"), r.surface->hasContent());
            o.insert(QStringLiteral("width"), r.surface->destinationSize().width());
            o.insert(QStringLiteral("height"), r.surface->destinationSize().height());
            o.insert(QStringLiteral("extendedSurface"), r.extendedSurfaces > 0);
            o.insert(QStringLiteral("properties"), QJsonObject::fromVariantMap(r.properties));
            o.insert(QStringLiteral("category"), r.properties.value(QStringLiteral("CATEGORY")).toString());
            surfaces.append(o);
        }
        QJsonObject root;
        root.insert(QStringLiteral("surfaces"), surfaces);
        QSaveFile f(m_reportPath);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(QJsonDocument(root).toJson());
            f.commit();
        }
    }

    void scheduleReport()
    {
        if (!m_pending) {
            m_pending = true;
            QTimer::singleShot(20, this, [this]() {
                m_pending = false;
                writeReport();
            });
        }
    }

private:
    QString m_reportPath;
    bool m_pending = false;
};

FakeLipstick *g_lipstick = nullptr;

// Points g_lipstick at main()'s compositor for the raw libwayland callbacks,
// and clears it when main() returns, so it never dangles.
class LipstickRegistration
{
public:
    explicit LipstickRegistration(FakeLipstick *lipstick) { g_lipstick = lipstick; }
    ~LipstickRegistration() { g_lipstick = nullptr; }
    LipstickRegistration(const LipstickRegistration &) = delete;
    LipstickRegistration &operator=(const LipstickRegistration &) = delete;
};

// ---- qt_extended_surface (server side, raw libwayland) -------------------

void extendedUpdateGenericProperty(wl_client *, wl_resource *resource, const char *name,
                                   wl_array *value)
{
    auto *surface = static_cast<QWaylandSurface *>(wl_resource_get_user_data(resource));
    if (!surface || !g_lipstick->records.contains(surface))
        return;
    QByteArray bytes(static_cast<const char *>(value->data), static_cast<int>(value->size));
    QDataStream ds(bytes);
    QVariant variant;
    ds >> variant;
    g_lipstick->records[surface].properties.insert(QString::fromUtf8(name), variant);
    std::cerr << "fake-lipstick: property " << name << "=" << variant.toString().toStdString()
              << " on surface '" << g_lipstick->records[surface].title.toStdString() << "'\n";
    g_lipstick->scheduleReport();
}
void extendedSetContentOrientationMask(wl_client *, wl_resource *, int32_t) {}
void extendedSetWindowFlags(wl_client *, wl_resource *, int32_t) {}
void extendedRaise(wl_client *, wl_resource *) {}
void extendedLower(wl_client *, wl_resource *) {}

const struct qt_extended_surface_interface kExtendedSurfaceImpl = {
    extendedUpdateGenericProperty,
    extendedSetContentOrientationMask,
    extendedSetWindowFlags,
    extendedRaise,
    extendedLower,
};

void getExtendedSurface(wl_client *client, wl_resource *resource, uint32_t id,
                        wl_resource *surfaceResource)
{
    QWaylandSurface *surface = QWaylandSurface::fromResource(surfaceResource);
    wl_resource *ext = wl_resource_create(client, &qt_extended_surface_interface,
                                          wl_resource_get_version(resource), id);
    wl_resource_set_implementation(ext, &kExtendedSurfaceImpl, surface, nullptr);
    if (surface && g_lipstick->records.contains(surface)) {
        g_lipstick->records[surface].extendedSurfaces++;
        g_lipstick->scheduleReport();
    }
}

const struct qt_surface_extension_interface kSurfaceExtensionImpl = {
    getExtendedSurface,
};

void bindSurfaceExtension(wl_client *client, void *, uint32_t version, uint32_t id)
{
    wl_resource *resource = wl_resource_create(client, &qt_surface_extension_interface,
                                               static_cast<int>(qMin<uint32_t>(version, 1)), id);
    wl_resource_set_implementation(resource, &kSurfaceExtensionImpl, nullptr, nullptr);
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QString socket = QStringLiteral("fake-lipstick-0");
    QString report = QStringLiteral("fake-lipstick.json");
    const QStringList args = QGuiApplication::arguments();
    for (int i = 1; i + 1 < args.size(); ++i) {
        if (args.at(i) == QLatin1String("--socket"))
            socket = args.at(i + 1);
        else if (args.at(i) == QLatin1String("--report"))
            report = args.at(i + 1);
    }

    FakeLipstick lipstick(report);
    const LipstickRegistration registration(&lipstick);
    QWaylandCompositor &compositor = lipstick.compositor;
    compositor.setSocketName(socket.toUtf8());

    auto *wlShell = new QWaylandWlShell(&compositor);
    auto *xdgShell = new QWaylandXdgShell(&compositor);

    QWindow screenWindow;
    screenWindow.resize(540, 960);
    lipstick.output = new QWaylandOutput(&compositor, &screenWindow);
    QWaylandOutputMode mode(QSize(540, 960), 60000);
    lipstick.output->addMode(mode, true);
    lipstick.output->setCurrentMode(mode);
    lipstick.output->setPhysicalSize(QSize(62, 110));

    QObject::connect(&compositor, &QWaylandCompositor::surfaceCreated, &lipstick,
                     [&lipstick](QWaylandSurface *surface) {
        SurfaceRecord r;
        r.surface = surface;
        r.view = new QWaylandView(surface);
        r.view->setSurface(surface);
        r.view->setOutput(lipstick.output);
        lipstick.records.insert(surface, r);
        QObject::connect(surface, &QWaylandSurface::hasContentChanged, &lipstick,
                         [&lipstick]() { lipstick.scheduleReport(); });
        QObject::connect(surface, &QWaylandSurface::destinationSizeChanged, &lipstick,
                         [&lipstick]() { lipstick.scheduleReport(); });
        QObject::connect(surface, &QWaylandSurface::surfaceDestroyed, &lipstick,
                         [&lipstick, surface]() {
            SurfaceRecord r = lipstick.records.take(surface);
            delete r.view;
            lipstick.scheduleReport();
        });
    });
    QObject::connect(wlShell, &QWaylandWlShell::wlShellSurfaceCreated, &lipstick,
                     [&lipstick](QWaylandWlShellSurface *ss) {
        QWaylandSurface *surface = ss->surface();
        lipstick.records[surface].role = QStringLiteral("wl_shell");
        auto update = [&lipstick, ss, surface]() {
            lipstick.records[surface].title = ss->title();
            lipstick.records[surface].className = ss->className();
            lipstick.scheduleReport();
        };
        QObject::connect(ss, &QWaylandWlShellSurface::titleChanged, &lipstick, update);
        QObject::connect(ss, &QWaylandWlShellSurface::classNameChanged, &lipstick, update);
        QObject::connect(ss, &QWaylandWlShellSurface::setFullScreen, &lipstick,
                         [ss](QWaylandWlShellSurface::FullScreenMethod, uint, QWaylandOutput *) {
            ss->sendConfigure(QSize(540, 960), QWaylandWlShellSurface::NoneEdge);
        });
        update();
    });
    QObject::connect(xdgShell, &QWaylandXdgShell::toplevelCreated, &lipstick,
                     [&lipstick](QWaylandXdgToplevel *tl, QWaylandXdgSurface *xs) {
        QWaylandSurface *surface = xs->surface();
        lipstick.records[surface].role = QStringLiteral("xdg_toplevel");
        auto update = [&lipstick, tl, surface]() {
            lipstick.records[surface].title = tl->title();
            lipstick.records[surface].className = tl->appId();
            lipstick.scheduleReport();
        };
        QObject::connect(tl, &QWaylandXdgToplevel::titleChanged, &lipstick, update);
        QObject::connect(tl, &QWaylandXdgToplevel::appIdChanged, &lipstick, update);
        update();
    });

    compositor.create();
    if (!compositor.isCreated()) {
        std::cerr << "fake-lipstick: cannot create compositor\n";
        return 1;
    }
    wl_global_create(compositor.display(), &qt_surface_extension_interface, 1, nullptr,
                     bindSurfaceExtension);

    // Frame pacing: release buffers and send frame callbacks at ~60 Hz.
    QTimer frameTimer;
    QObject::connect(&frameTimer, &QTimer::timeout, &lipstick, [&lipstick]() {
        lipstick.output->frameStarted();
        for (auto it = lipstick.records.begin(); it != lipstick.records.end(); ++it) {
            if (it.value().view)
                it.value().view->advance();
        }
        lipstick.output->sendFrameCallbacks();
    });
    frameTimer.start(16);

    lipstick.writeReport();
    std::cout << "ready " << compositor.socketName().constData() << "\n" << std::flush;
    return QGuiApplication::exec();
}
