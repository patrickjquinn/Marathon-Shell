#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QSignalSpy>
#include <QTest>

#include "portalfilechooser.h"

// xdg-desktop-portal's side: it calls the backend with a request handle and
// waits for the reply, or closes the request.
class TestPortalFileChooser : public QObject {
    Q_OBJECT

    QObject            desktop;
    FileChooserPortal *portal = nullptr;
    int                serial = 0;

    static QDBusConnection caller() {
        return QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                             QStringLiteral("xdg-desktop-portal"));
    }

    QDBusPendingCall call(const QString &method, const QString &handle, const QVariantMap &options,
                          const QString &title = QStringLiteral("Open")) {
        QDBusMessage message = QDBusMessage::createMethodCall(
            QDBusConnection::sessionBus().baseService(), QStringLiteral("/org/freedesktop/portal/desktop"),
            QStringLiteral("org.freedesktop.impl.portal.FileChooser"), method);
        message.setArguments({QVariant::fromValue(QDBusObjectPath(handle)), QStringLiteral("org.example.App"),
                              QStringLiteral("wayland:abc"), title, options});
        return caller().asyncCall(message, 10000);
    }

    QString handle() {
        return QStringLiteral("/org/freedesktop/portal/desktop/request/1_1/t%1").arg(++serial);
    }

    static void wait(const QDBusPendingCall &pending) {
        QDeadlineTimer deadline(5000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(10);
    }

    static QVariant filters(const QList<PortalFilter> &list) {
        QDBusArgument arg;
        arg << list;
        return QVariant::fromValue(arg);
    }

  private slots:
    void initTestCase() {
        portal = new FileChooserPortal(QDBusConnection::sessionBus(), this);
        new FileChooserAdaptor(&desktop, portal);
        QVERIFY(QDBusConnection::sessionBus().registerObject(
            QStringLiteral("/org/freedesktop/portal/desktop"), &desktop,
            QDBusConnection::ExportAdaptors));
    }

    void openingAPictureAnswersWithItsUri() {
        QSignalSpy       requested(portal, &FileChooserPortal::requested);
        const PortalFilter images{QStringLiteral("Images"),
                                  {{1u, QStringLiteral("image/*")}, {0u, QStringLiteral("*.webp")}}};
        const QDBusPendingCall pending =
            call(QStringLiteral("OpenFile"), handle(),
                 {{QStringLiteral("multiple"), true},
                  {QStringLiteral("accept_label"), QStringLiteral("Attach")},
                  {QStringLiteral("filters"), filters({images})},
                  {QStringLiteral("current_folder"), QByteArray("/home/u/Pictures\0", 17)}});
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(request.value("mode").toString(), QStringLiteral("open"));
        QCOMPARE(request.value("acceptLabel").toString(), QStringLiteral("Attach"));
        QVERIFY(request.value("multiple").toBool());
        QCOMPARE(request.value("folder").toString(), QStringLiteral("/home/u/Pictures"));
        const QVariantMap filter = request.value("filters").toList().value(0).toMap();
        QCOMPARE(filter.value("mimes").toStringList(), QStringList{QStringLiteral("image/*")});
        QCOMPARE(filter.value("globs").toStringList(), QStringList{QStringLiteral("*.webp")});

        portal->accept({QStringLiteral("/home/u/Pictures/a b.png"), QStringLiteral("/home/u/Pictures/c.png")},
                       0, {});
        wait(pending);
        const QDBusMessage reply = pending.reply();
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(reply.arguments().value(0).toUInt(), 0u);
        const QVariantMap results = qdbus_cast<QVariantMap>(reply.arguments().value(1));
        QCOMPARE(results.value("uris").toStringList(),
                 QStringList({QStringLiteral("file:///home/u/Pictures/a%20b.png"),
                              QStringLiteral("file:///home/u/Pictures/c.png")}));
        const PortalFilter current = qdbus_cast<PortalFilter>(results.value("current_filter"));
        QCOMPARE(current.name, QStringLiteral("Images"));
    }

    void cancellingAnswersCancelled() {
        QSignalSpy             requested(portal, &FileChooserPortal::requested);
        const QDBusPendingCall pending = call(QStringLiteral("OpenFile"), handle(), {});
        QTRY_COMPARE(requested.size(), 1);
        portal->cancel();
        wait(pending);
        QCOMPARE(pending.reply().arguments().value(0).toUInt(), 1u);
    }

    void closingTheRequestEndsIt() {
        QSignalSpy             requested(portal, &FileChooserPortal::requested);
        QSignalSpy             closed(portal, &FileChooserPortal::closed);
        const QString          path    = handle();
        const QDBusPendingCall pending = call(QStringLiteral("OpenFile"), path, {});
        QTRY_COMPARE(requested.size(), 1);
        QDBusMessage close = QDBusMessage::createMethodCall(
            QDBusConnection::sessionBus().baseService(), path,
            QStringLiteral("org.freedesktop.impl.portal.Request"), QStringLiteral("Close"));
        wait(caller().asyncCall(close));
        wait(pending);
        QCOMPARE(pending.reply().arguments().value(0).toUInt(), 2u);
        QCOMPARE(closed.size(), 1);
        portal->accept({QStringLiteral("/tmp/late")}, -1, {});
    }

    void savingSuggestsTheName() {
        QSignalSpy             requested(portal, &FileChooserPortal::requested);
        const QDBusPendingCall pending =
            call(QStringLiteral("SaveFile"), handle(),
                 {{QStringLiteral("current_name"), QStringLiteral("notes.txt")},
                  {QStringLiteral("current_folder"), QByteArray("/home/u/Documents\0", 18)}},
                 QStringLiteral("Save"));
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(request.value("mode").toString(), QStringLiteral("save"));
        QCOMPARE(request.value("name").toString(), QStringLiteral("notes.txt"));
        QCOMPARE(request.value("folder").toString(), QStringLiteral("/home/u/Documents"));
        portal->accept({QStringLiteral("/home/u/Documents/notes.txt")}, -1, {});
        wait(pending);
        const QVariantMap results = qdbus_cast<QVariantMap>(pending.reply().arguments().value(1));
        QCOMPARE(results.value("uris").toStringList(),
                 QStringList{QStringLiteral("file:///home/u/Documents/notes.txt")});
    }

    void savingSeveralPicksAFolder() {
        QSignalSpy requested(portal, &FileChooserPortal::requested);
        QDBusArgument files;
        files << QList<QByteArray>{QByteArray("a.txt\0", 6), QByteArray("b.txt\0", 6)};
        const QDBusPendingCall pending =
            call(QStringLiteral("SaveFiles"), handle(), {{QStringLiteral("files"), QVariant::fromValue(files)}},
                 QStringLiteral("Save"));
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(request.value("mode").toString(), QStringLiteral("saveMany"));
        QVERIFY(request.value("directory").toBool());
        QCOMPARE(request.value("files").toStringList(),
                 QStringList({QStringLiteral("a.txt"), QStringLiteral("b.txt")}));
        portal->accept({QStringLiteral("/home/u/Documents")}, -1, {});
        wait(pending);
        const QVariantMap results = qdbus_cast<QVariantMap>(pending.reply().arguments().value(1));
        QCOMPARE(results.value("uris").toStringList(),
                 QStringList({QStringLiteral("file:///home/u/Documents/a.txt"),
                              QStringLiteral("file:///home/u/Documents/b.txt")}));
    }

    void choicesComeBack() {
        QSignalSpy         requested(portal, &FileChooserPortal::requested);
        const PortalChoice encoding{QStringLiteral("encoding"),
                                    QStringLiteral("Encoding"),
                                    {{QStringLiteral("utf8"), QStringLiteral("UTF-8")},
                                     {QStringLiteral("latin1"), QStringLiteral("Latin-1")}},
                                    QStringLiteral("utf8")};
        QDBusArgument choices;
        choices << QList<PortalChoice>{encoding};
        const QDBusPendingCall pending =
            call(QStringLiteral("OpenFile"), handle(), {{QStringLiteral("choices"), QVariant::fromValue(choices)}});
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap choice = requested.at(0).at(0).toMap().value("choices").toList().value(0).toMap();
        QCOMPARE(choice.value("id").toString(), QStringLiteral("encoding"));
        QCOMPARE(choice.value("value").toString(), QStringLiteral("utf8"));
        QCOMPARE(choice.value("options").toList().size(), 2);
        portal->accept({QStringLiteral("/tmp/x")}, -1, {{QStringLiteral("encoding"), QStringLiteral("latin1")}});
        wait(pending);
        const QVariantMap results = qdbus_cast<QVariantMap>(pending.reply().arguments().value(1));
        const auto chosen = qdbus_cast<QList<PortalChosen>>(results.value("choices"));
        QCOMPARE(chosen.size(), 1);
        QCOMPARE(chosen.at(0).value, QStringLiteral("latin1"));
    }

    void aNewerRequestClosesTheOlder() {
        QSignalSpy             requested(portal, &FileChooserPortal::requested);
        const QDBusPendingCall first  = call(QStringLiteral("OpenFile"), handle(), {});
        QTRY_COMPARE(requested.size(), 1);
        const QDBusPendingCall second = call(QStringLiteral("OpenFile"), handle(), {});
        QTRY_COMPARE(requested.size(), 2);
        wait(first);
        QCOMPARE(first.reply().arguments().value(0).toUInt(), 2u);
        portal->cancel();
        wait(second);
        QCOMPARE(second.reply().arguments().value(0).toUInt(), 1u);
    }
};

QTEST_GUILESS_MAIN(TestPortalFileChooser)
#include "test_portalfilechooser.moc"
