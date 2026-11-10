// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-test-client: a minimal Qt6 "Keel app" for the end-to-end test. It
// follows the client side of PROTOCOL.md: a main window, a cover window
// whose title is $KEEL_SHELL_COVER_TITLE, and a peer D-Bus connection to
// $KEEL_SHELL_DBUS. Uses QRasterWindow so buffers are wl_shm (headless CI).

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QRasterWindow>
#include <QSaveFile>
#include <QTimer>

class ColorWindow : public QRasterWindow
{
public:
    explicit ColorWindow(const QColor &c) : m_color(c) {}
    bool exposedOnce = false;

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(QRect(QPoint(), size()), m_color);
    }
    void exposeEvent(QExposeEvent *e) override
    {
        if (isExposed())
            exposedOnce = true;
        QRasterWindow::exposeEvent(e);
    }

private:
    QColor m_color;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QString reportPath;
    bool lateCover = false;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i) == QLatin1String("--report") && i + 1 < args.size())
            reportPath = args.at(++i);
        else if (args.at(i) == QLatin1String("--late-cover"))
            lateCover = true;
    }

    const QString coverTitle = qEnvironmentVariable("KEEL_SHELL_COVER_TITLE", QStringLiteral("keel:cover"));

    ColorWindow mainWindow(QColor(200, 40, 40, 255));
    mainWindow.setTitle(QStringLiteral("Keel Test Main"));
    mainWindow.resize(300, 500);
    mainWindow.show();

    ColorWindow coverWindow(QColor(40, 40, 200, 200));
    coverWindow.setTitle(lateCover ? QStringLiteral("not yet a cover") : coverTitle + QStringLiteral(":Test"));
    coverWindow.resize(234, 374);
    coverWindow.show();
    if (lateCover) {
        QTimer::singleShot(700, &coverWindow, [&]() {
            coverWindow.setTitle(coverTitle);
        });
    }

    QJsonObject report;
    report.insert(QStringLiteral("KEEL_SHELL"), qEnvironmentVariable("KEEL_SHELL"));
    report.insert(QStringLiteral("WAYLAND_DISPLAY"), qEnvironmentVariable("WAYLAND_DISPLAY"));
    report.insert(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"),
                  qEnvironmentVariable("QT_WAYLAND_SHELL_INTEGRATION"));
    report.insert(QStringLiteral("QT_WAYLAND_FORCE_DPI"), qEnvironmentVariable("QT_WAYLAND_FORCE_DPI"));
    report.insert(QStringLiteral("FLATPAK_MALIIT_CONTAINER_DBUS"),
                  qEnvironmentVariable("FLATPAK_MALIIT_CONTAINER_DBUS"));
    report.insert(QStringLiteral("platform"), QGuiApplication::platformName());

    auto writeReport = [&]() {
        report.insert(QStringLiteral("mainExposed"), mainWindow.exposedOnce);
        report.insert(QStringLiteral("coverExposed"), coverWindow.exposedOnce);
        if (reportPath.isEmpty())
            return;
        QSaveFile f(reportPath);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(QJsonDocument(report).toJson());
            f.commit();
        }
    };

    const QString address = qEnvironmentVariable("KEEL_SHELL_DBUS");
    QDBusConnection bus = QDBusConnection::connectToPeer(address, QStringLiteral("keel-shell"));
    report.insert(QStringLiteral("dbusConnected"), bus.isConnected());
    if (bus.isConnected()) {
        QDBusMessage ping = QDBusMessage::createMethodCall(
                QString(), QStringLiteral("/org/shipwright/keel/Shell"),
                QStringLiteral("org.shipwright.keel.Shell1"), QStringLiteral("Ping"));
        const QDBusMessage reply = bus.call(ping, QDBus::Block, 5000);
        report.insert(QStringLiteral("ping"), reply.arguments().value(0).toString());

        QDBusMessage get = QDBusMessage::createMethodCall(
                QString(), QStringLiteral("/org/shipwright/keel/Shell"),
                QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        get << QStringLiteral("org.shipwright.keel.Shell1") << QStringLiteral("Dpi");
        const QDBusMessage dpi = bus.call(get, QDBus::Block, 5000);
        report.insert(QStringLiteral("dpi"),
                      dpi.arguments().value(0).value<QDBusVariant>().variant().toInt());

        // Content orientation round trip.
        QDBusMessage set = QDBusMessage::createMethodCall(
                QString(), QStringLiteral("/org/shipwright/keel/Shell"),
                QStringLiteral("org.shipwright.keel.Shell1"), QStringLiteral("SetContentOrientation"));
        set << 0;
        bus.call(set, QDBus::Block, 5000);

        bus.connect(QString(), QStringLiteral("/org/shipwright/keel/Shell"),
                    QStringLiteral("org.shipwright.keel.Shell1"), QStringLiteral("CloseRequested"),
                    &app, SLOT(quit()));
    }

    QTimer reportTimer;
    QObject::connect(&reportTimer, &QTimer::timeout, &app, writeReport);
    reportTimer.start(200);
    writeReport();
    return app.exec();
}
