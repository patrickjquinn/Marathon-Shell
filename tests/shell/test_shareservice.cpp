#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusUnixFileDescriptor>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QClipboard>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <unistd.h>

#include "dbusnormalize.h"
#include "marathonappregistry.h"
#include "shareservice.h"

// A Keel app's ShareProvider, as the share sheet reaches it.
class FakeProvider : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.share")

  public:
    QList<QVariantMap> received;
    QByteArray         fileContent;

  public slots:
    Q_SCRIPTABLE void share(const QVariantMap &configuration) {
        const QVariantMap  config = normalizeMapDeep(configuration);
        const QVariantList list   = config.value(QStringLiteral("resources")).toList();
        for (const QVariant &resource : list) {
            const QVariant fd = resource.toMap().value(QStringLiteral("fileDescriptor"));
            if (fd.canConvert<QDBusUnixFileDescriptor>()) {
                QFile file;
                if (file.open(dup(fd.value<QDBusUnixFileDescriptor>().fileDescriptor()),
                              QIODevice::ReadOnly, QFileDevice::AutoCloseHandle))
                    fileContent = file.readAll();
            }
        }
        received << config;
    }
};

class TestShareService : public QObject {
    Q_OBJECT

    QTemporaryDir       home;
    MarathonAppRegistry registry;
    QStringList         raised;
    QString             caller = QStringLiteral("gallery");
    ShareService       *service = nullptr;

    QString picture() const {
        return home.filePath(QStringLiteral("Pictures/beach.png"));
    }

    void addApp(const QString &id, const QString &shareMethods) {
        const QString dir = home.filePath(QStringLiteral("apps/") + id);
        QVERIFY(QDir().mkpath(dir));
        QFile manifest(dir + QStringLiteral("/manifest.json"));
        QVERIFY(manifest.open(QIODevice::WriteOnly));
        manifest.write(QStringLiteral("{\"id\":\"%1\",\"shareMethods\":%2}").arg(id, shareMethods).toUtf8());
        registry.registerApp(id, id.toUpper(), QStringLiteral("icon.svg"), 0, dir,
                             QStringLiteral("Main.qml"), QStringLiteral("1.0"), false, {});
    }

    static QDBusMessage share(const QVariantMap &configuration) {
        QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                            QStringLiteral("gallery-app"));
        QDBusMessage call = QDBusMessage::createMethodCall(
            QStringLiteral("org.sailfishos.share"), QStringLiteral("/"),
            QStringLiteral("org.sailfishos.share"), QStringLiteral("share"));
        call.setArguments({configuration});
        QDBusPendingCall pending = bus.asyncCall(call, 5000);
        QDeadlineTimer   deadline(5000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(10);
        return pending.reply();
    }

    static QStringList ids(const QVariantMap &request) {
        QStringList out;
        const QVariantList targets = request.value(QStringLiteral("targets")).toList();
        for (const QVariant &t : targets)
            out << t.toMap().value(QStringLiteral("id")).toString();
        return out;
    }

  private slots:
    void initTestCase() {
        QVERIFY(QDir().mkpath(home.filePath(QStringLiteral("Pictures"))));
        QFile png(picture());
        QVERIFY(png.open(QIODevice::WriteOnly));
        png.write("\x89PNG not really");
        png.close();
        addApp(QStringLiteral("notes"),
               QStringLiteral("[{\"name\":\"text\",\"title\":\"New note\",\"mimeTypes\":[\"text/plain\",\"text/x-url\"]}]"));
        addApp(QStringLiteral("email"),
               QStringLiteral("[{\"name\":\"attach\",\"title\":\"Email\",\"mimeTypes\":[\"image/*\"]}]"));
        addApp(QStringLiteral("gallery"), QStringLiteral("[]"));
        service = new ShareService(
            &registry, {home.filePath(QStringLiteral("Pictures"))},
            [this](qint64) { return caller; }, [this](const QString &id) { raised << id; }, this);
        QVERIFY(service->registerOnSessionBus());
    }

    void typesMatch_data() {
        QTest::addColumn<QString>("accepted");
        QTest::addColumn<QString>("mimeType");
        QTest::addColumn<bool>("matches");
        QTest::newRow("same") << "text/plain" << "text/plain" << true;
        QTest::newRow("other") << "text/plain" << "image/png" << false;
        QTest::newRow("kind") << "image/*" << "image/png" << true;
        QTest::newRow("any") << "*/*" << "video/mp4" << true;
        QTest::newRow("asked for a kind") << "image/jpeg" << "image/*" << true;
        QTest::newRow("prefix is no kind") << "image/*" << "imagex/png" << false;
    }

    void typesMatch() const {
        QFETCH(QString, accepted);
        QFETCH(QString, mimeType);
        QFETCH(bool, matches);
        QCOMPARE(ShareService::mimeMatches(accepted, mimeType), matches);
    }

    void onlySharedFilesOpen() const {
        const QStringList shared{home.filePath(QStringLiteral("Pictures"))};
        const qint64      self = QCoreApplication::applicationPid();
        QString           host;
        const int         fd = ShareService::openShared(self, picture(), shared, &host);
        QVERIFY(fd >= 0);
        ::close(fd);
        QCOMPARE(host, QFileInfo(picture()).canonicalFilePath());

        QFile secret(home.filePath(QStringLiteral("secret.txt")));
        QVERIFY(secret.open(QIODevice::WriteOnly));
        secret.close();
        QVERIFY(QFile::link(secret.fileName(), home.filePath(QStringLiteral("Pictures/link.png"))));
        QCOMPARE(ShareService::openShared(self, secret.fileName(), shared, &host), -1);
        QCOMPARE(ShareService::openShared(self, home.filePath(QStringLiteral("Pictures/link.png")),
                                          shared, &host),
                 -1);
        QCOMPARE(ShareService::openShared(self,
                                          home.filePath(QStringLiteral("Pictures/../secret.txt")),
                                          shared, &host),
                 -1);
        QCOMPARE(ShareService::openShared(self, home.filePath(QStringLiteral("Pictures")), shared,
                                          &host),
                 -1);
        QCOMPARE(ShareService::openShared(self, QStringLiteral("Pictures/beach.png"), shared, &host),
                 -1);
    }

    void textGoesToTheAppChosen() {
        QSignalSpy requested(service, &ShareService::requested);
        QSignalSpy delivered(service, &ShareService::delivered);
        const QDBusMessage reply = share(
            {{QStringLiteral("mimeType"), QStringLiteral("text/plain")},
             {QStringLiteral("resources"),
              QVariantList{QVariantMap{{QStringLiteral("name"), QStringLiteral("Note")},
                                       {QStringLiteral("data"), QStringLiteral("Buy milk")}}}}});
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(ids(request), QStringList({QStringLiteral("notes/text"), QStringLiteral("clipboard")}));
        QCOMPARE(request.value(QStringLiteral("text")).toString(), QStringLiteral("Buy milk"));

        // The app starts while the sheet hands over: its name comes later.
        service->choose(QStringLiteral("notes/text"));
        QCOMPARE(raised, QStringList{QStringLiteral("notes")});
        QTest::qWait(300);
        FakeProvider    notes;
        QDBusConnection app = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                            QStringLiteral("notes-app"));
        QVERIFY(app.registerService(QStringLiteral("org.marathonos.notes")));
        QVERIFY(app.registerObject(QStringLiteral("/share/text"), &notes,
                                   QDBusConnection::ExportScriptableSlots));
        QTRY_COMPARE(delivered.size(), 1);
        QCOMPARE(notes.received.size(), 1);
        const QVariantMap first =
            notes.received.at(0).value(QStringLiteral("resources")).toList().value(0).toMap();
        QCOMPARE(first.value(QStringLiteral("data")).toString(), QStringLiteral("Buy milk"));
        app.unregisterService(QStringLiteral("org.marathonos.notes"));
    }

    void textCopies() {
        QSignalSpy requested(service, &ShareService::requested);
        share({{QStringLiteral("resources"),
                QVariantList{QVariantMap{{QStringLiteral("linkTitle"), QStringLiteral("Marathon")},
                                         {QStringLiteral("status"),
                                          QStringLiteral("https://marathonos.org")}}}}});
        QTRY_COMPARE(requested.size(), 1);
        service->choose(QStringLiteral("clipboard"));
        QCOMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("https://marathonos.org"));
    }

    void aPictureGoesAsAFile() {
        QSignalSpy requested(service, &ShareService::requested);
        QSignalSpy delivered(service, &ShareService::delivered);
        FakeProvider    email;
        QDBusConnection app = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                            QStringLiteral("email-app"));
        QVERIFY(app.registerService(QStringLiteral("org.marathonos.email")));
        QVERIFY(app.registerObject(QStringLiteral("/share/attach"), &email,
                                   QDBusConnection::ExportScriptableSlots));

        share({{QStringLiteral("mimeType"), QStringLiteral("image/*")},
               {QStringLiteral("resources"), QVariantList{picture()}}});
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(ids(request), QStringList{QStringLiteral("email/attach")});
        QCOMPARE(request.value(QStringLiteral("image")).toString(),
                 QUrl::fromLocalFile(QFileInfo(picture()).canonicalFilePath()).toString());

        service->choose(QStringLiteral("email/attach"));
        QTRY_COMPARE(delivered.size(), 1);
        QCOMPARE(email.fileContent, QByteArray("\x89PNG not really"));
        const QVariantMap first =
            email.received.at(0).value(QStringLiteral("resources")).toList().value(0).toMap();
        QCOMPARE(first.value(QStringLiteral("name")).toString(), QStringLiteral("beach.png"));
        app.unregisterService(QStringLiteral("org.marathonos.email"));
    }

    void aFileFromNoAppIsRefused() {
        QSignalSpy requested(service, &ShareService::requested);
        caller.clear();
        const QDBusMessage reply = share({{QStringLiteral("resources"), QVariantList{picture()}}});
        caller = QStringLiteral("gallery");
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.AccessDenied"));
        QTest::qWait(50);
        QCOMPARE(requested.size(), 0);
    }

    void theSharingAppIsNoTarget() {
        QSignalSpy requested(service, &ShareService::requested);
        caller = QStringLiteral("notes");
        share({{QStringLiteral("resources"),
                QVariantList{QVariantMap{{QStringLiteral("data"), QStringLiteral("x")}}}}});
        caller = QStringLiteral("gallery");
        QTRY_COMPARE(requested.size(), 1);
        QCOMPARE(ids(requested.at(0).at(0).toMap()), QStringList{QStringLiteral("clipboard")});
    }

    void tooManyResourcesAreRefused() {
        QVariantList many;
        for (int i = 0; i < 33; ++i)
            many << QVariantMap{{QStringLiteral("data"), QStringLiteral("x")}};
        const QDBusMessage reply = share({{QStringLiteral("resources"), many}});
        QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs"));
    }
};

QTEST_MAIN(TestShareService)
#include "test_shareservice.moc"
