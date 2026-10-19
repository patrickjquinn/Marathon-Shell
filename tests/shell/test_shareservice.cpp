#include <QDBusConnection>
#include <QDBusMetaType>
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

#include <fcntl.h>
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

// deckardd's Deckard1.Share: Android's share targets, and a share to one.
class FakeDeckard : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Deckard1.Share")

  public:
    QStringList        askedTypes;
    QString            sharedTo;
    QVariantMap        shared;
    QByteArray         sharedFile;

  public slots:
    QList<QVariantMap> ShareTargets(const QString &mimeType) {
        askedTypes << mimeType;
        return {{{"id", "org.signal/.Share"}, {"pkg", "org.signal"}, {"label", "Signal"},
                 {"icon", "data:image/png;base64,AA=="}, {"multiple", true}},
                {{"id", "org.k9/.Compose"}, {"pkg", "org.k9"}, {"label", "K-9"}, {"icon", ""},
                 {"multiple", false}},
                {{"id", "org.files/.Send"}, {"pkg", "org.files"}, {"label", "Files"}, {"icon", ""},
                 {"multiple", true}}};
    }
    void Share(const QString &id, const QVariantMap &configuration) {
        sharedTo = id;
        shared   = normalizeMapDeep(configuration);
        const QVariantList list = shared.value("resources").toList();
        for (const QVariant &resource : list) {
            const QVariant fd = resource.toMap().value("fileDescriptor");
            if (fd.canConvert<QDBusUnixFileDescriptor>()) {
                QFile file;
                if (file.open(dup(fd.value<QDBusUnixFileDescriptor>().fileDescriptor()),
                              QIODevice::ReadOnly, QFileDevice::AutoCloseHandle))
                    sharedFile = file.readAll();
            }
        }
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

    static QDBusMessage shareFiles(const QVariantList &resources, const QVariantMap &extra = {}) {
        QVariantMap config{{QStringLiteral("resources"), resources}};
        config.insert(extra);
        return share(config);
    }

    QVariantMap descriptorResource(const QString &name, const QString &path) {
        const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_CLOEXEC);
        const QVariantMap out{{QStringLiteral("name"), name},
                              {QStringLiteral("fileDescriptor"), QVariant::fromValue(QDBusUnixFileDescriptor(fd))}};
        ::close(fd);
        return out;
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

    // deckardd hands files over as descriptors; a descriptor is its own
    // proof of access, whoever sends it.
    void aDescriptorIsAcceptedFromAnyCaller() {
        QSignalSpy requested(service, &ShareService::requested);
        QSignalSpy delivered(service, &ShareService::delivered);
        caller.clear();
        const QDBusMessage reply = shareFiles({descriptorResource(QStringLiteral("../sea.png"), picture())});
        caller = QStringLiteral("gallery");
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QTRY_COMPARE(requested.size(), 1);
        const QVariantMap request = requested.at(0).at(0).toMap();
        QCOMPARE(request.value(QStringLiteral("mimeType")).toString(), QStringLiteral("image/png"));
        QVERIFY(ids(request).contains(QStringLiteral("email/attach")));
        QVERIFY(!ids(request).contains(QStringLiteral("clipboard")));
        QVERIFY(request.value(QStringLiteral("image")).toString().startsWith(QStringLiteral("file:///proc/self/fd/")));

        FakeProvider    email;
        QDBusConnection app = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                            QStringLiteral("email-app-2"));
        QVERIFY(app.registerService(QStringLiteral("org.marathonos.email")));
        QVERIFY(app.registerObject(QStringLiteral("/share/attach"), &email,
                                   QDBusConnection::ExportScriptableSlots));
        service->choose(QStringLiteral("email/attach"));
        QTRY_COMPARE(delivered.size(), 1);
        QCOMPARE(email.fileContent, QByteArray("\x89PNG not really"));
        QCOMPARE(email.received.at(0).value("resources").toList().value(0).toMap().value("name").toString(),
                 QStringLiteral("sea.png"));
        app.unregisterService(QStringLiteral("org.marathonos.email"));
    }

    void aDescriptorThatIsNoFileIsRefused() {
        int fds[2];
        QVERIFY(::pipe(fds) == 0);
        const QVariantMap pipe{{QStringLiteral("name"), QStringLiteral("x.png")},
                               {QStringLiteral("fileDescriptor"), QVariant::fromValue(QDBusUnixFileDescriptor(fds[0]))}};
        ::close(fds[0]);
        ::close(fds[1]);
        const QDBusMessage reply = shareFiles({pipe});
        QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs"));
    }

    // The sharing app named by a session service (deckardd's waydroid.<pkg>,
    // or a Marathon app) is no target; an app cannot name another one.
    void aServicesSourceIsLeftOut() {
        QSignalSpy requested(service, &ShareService::requested);
        caller = QStringLiteral("service:deckardd.service");
        share({{QStringLiteral("resources"), QVariantList{QVariantMap{{QStringLiteral("data"), QStringLiteral("x")}}}},
               {QStringLiteral("source"), QStringLiteral("notes")}});
        QTRY_COMPARE(requested.size(), 1);
        QCOMPARE(ids(requested.at(0).at(0).toMap()), QStringList{QStringLiteral("clipboard")});

        caller = QStringLiteral("gallery");
        share({{QStringLiteral("resources"), QVariantList{QVariantMap{{QStringLiteral("data"), QStringLiteral("x")}}}},
               {QStringLiteral("source"), QStringLiteral("notes")}});
        QTRY_COMPARE(requested.size(), 2);
        QVERIFY(ids(requested.at(1).at(0).toMap()).contains(QStringLiteral("notes/text")));
    }

    // Android's targets come after Marathon's, when deckardd answers.
    void androidAppsJoinTheSheet() {
        FakeDeckard     deckard;
        QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                            QStringLiteral("deckardd"));
        qDBusRegisterMetaType<QList<QVariantMap>>();
        QVERIFY(bus.registerObject(QStringLiteral("/org/marathonos/Deckard"), &deckard,
                                   QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerService(QStringLiteral("org.marathonos.Deckard")));
        QSignalSpy added(service, &ShareService::targetsAdded);
        QSignalSpy delivered(service, &ShareService::delivered);

        caller = QStringLiteral("service:deckardd.service");
        shareFiles({descriptorResource(QStringLiteral("a.png"), picture()),
                    descriptorResource(QStringLiteral("b.png"), picture())},
                   {{QStringLiteral("mimeType"), QStringLiteral("image/png")},
                    {QStringLiteral("source"), QStringLiteral("waydroid.org.files")}});
        caller = QStringLiteral("gallery");
        QTRY_COMPARE(added.size(), 1);
        QCOMPARE(deckard.askedTypes, QStringList{QStringLiteral("image/png")});
        const QVariantList android = added.at(0).at(0).toList();
        QCOMPARE(android.size(), 1);
        QCOMPARE(android.at(0).toMap().value("id").toString(), QStringLiteral("android:org.signal/.Share"));
        QCOMPARE(android.at(0).toMap().value("name").toString(), QStringLiteral("Signal"));
        QCOMPARE(android.at(0).toMap().value("icon").toString(), QStringLiteral("data:image/png;base64,AA=="));

        service->choose(QStringLiteral("android:org.signal/.Share"));
        QTRY_COMPARE(delivered.size(), 1);
        QCOMPARE(deckard.sharedTo, QStringLiteral("org.signal/.Share"));
        QCOMPARE(deckard.shared.value("resources").toList().size(), 2);
        QCOMPARE(deckard.sharedFile, QByteArray("\x89PNG not really"));
        QVERIFY(!raised.contains(QStringLiteral("android:org.signal/.Share")));
        bus.unregisterService(QStringLiteral("org.marathonos.Deckard"));
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
