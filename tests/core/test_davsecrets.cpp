#include <QDBusConnection>
#include <QDBusMessage>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>

#include "davsecretstore.h"
#include "davsyncengine.h"

class FakeSecretStore : public DavSecretStore {
    Q_OBJECT

  public:
    bool                    available = true;
    QHash<QString, QString> items;
    QStringList             loads;

    void                    store(const QString &id, const QString &, const QString &secret,
                                  const Done &done) override {
        answer(done, [this, id, secret] {
            items.insert(id, secret);
            return Result::Ok;
        });
    }
    void load(const QString &id, const Done &done) override {
        loads << id;
        QTimer::singleShot(0, this, [this, id, done] {
            if (!available)
                done(Result::Unavailable, {});
            else if (items.contains(id))
                done(Result::Ok, items.value(id));
            else
                done(Result::NotFound, {});
        });
    }
    void remove(const QString &id, const Done &done) override {
        answer(done, [this, id] { return items.remove(id) ? Result::Ok : Result::NotFound; });
    }

  private:
    void answer(const Done &done, const std::function<Result()> &op) {
        QTimer::singleShot(0, this,
                           [this, done, op] { done(available ? op() : Result::Unavailable, {}); });
    }
};

// A private session bus, optionally with a real gnome-keyring on it.
struct KeyringBus {
    QTemporaryDir dir;
    QProcess      daemon;
    QProcess      keyring;
    QString       address;

    ~KeyringBus() {
        keyring.kill();
        keyring.waitForFinished();
        daemon.kill();
        daemon.waitForFinished();
    }

    bool start() {
        QFile c(dir.filePath("bus.conf"));
        if (!c.open(QIODevice::WriteOnly))
            return false;
        c.write(QStringLiteral("<busconfig><type>session</type><listen>unix:tmpdir=%1</listen>"
                               "<policy context=\"default\"><allow send_destination=\"*\"/>"
                               "<allow eavesdrop=\"true\"/><allow own=\"*\"/></policy></busconfig>")
                    .arg(dir.path())
                    .toUtf8());
        c.close();
        daemon.start("dbus-daemon",
                     {"--config-file=" + c.fileName(), "--nofork", "--print-address"});
        if (!daemon.waitForReadyRead(5000))
            return false;
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        return !address.isEmpty();
    }

    // The session script's setup: a plaintext "login" keyring as default, unlocked.
    bool startKeyring(QDBusConnection &bus) {
        const QString keyrings = dir.filePath("home/.local/share/keyrings");
        QDir().mkpath(keyrings);
        QDir().mkpath(dir.filePath("run"));
        QFile login(keyrings + "/login.keyring");
        QFile def(keyrings + "/default");
        if (!login.open(QIODevice::WriteOnly) || !def.open(QIODevice::WriteOnly))
            return false;
        login.write("[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\n"
                    "lock-after=false\n");
        def.write("login");
        login.close();
        def.close();
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("DBUS_SESSION_BUS_ADDRESS", address);
        env.insert("HOME", dir.filePath("home"));
        env.insert("XDG_DATA_HOME", dir.filePath("home/.local/share"));
        env.insert("XDG_RUNTIME_DIR", dir.filePath("run"));
        keyring.setProcessEnvironment(env);
        keyring.start("gnome-keyring-daemon", {"--components=secrets", "--foreground"});
        if (!keyring.waitForStarted(5000))
            return false;
        for (int i = 0; i < 50; ++i) {
            QDBusMessage unlock = QDBusMessage::createMethodCall(
                "org.freedesktop.secrets", "/org/freedesktop/secrets",
                "org.freedesktop.Secret.Service", "Unlock");
            unlock << QVariant::fromValue(QList<QDBusObjectPath>{
                QDBusObjectPath("/org/freedesktop/secrets/collection/login")});
            if (bus.call(unlock).type() == QDBusMessage::ReplyMessage)
                return true;
            QTest::qWait(100);
        }
        return false;
    }
};

struct Answer {
    bool                   done = false;
    DavSecretStore::Result result{};
    QString                secret;

    DavSecretStore::Done   callback() {
        return [this](DavSecretStore::Result r, const QString &s) {
            done   = true;
            result = r;
            secret = s;
        };
    }
};

class TestDavSecrets : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    static void   writeAccount(const QString &id, const QString &secret) {
        QSettings s;
        s.beginGroup("dav/accounts/" + id);
        s.setValue("displayName", "Nextcloud");
        s.setValue("username", "pat");
        if (!secret.isEmpty())
            s.setValue("secret", secret);
        s.endGroup();
    }

    static QVariant plaintext(const QString &id) {
        return QSettings().value("dav/accounts/" + id + "/secret");
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
        QCoreApplication::setOrganizationName("marathon-os");
        QCoreApplication::setApplicationName("test-davsecrets");
        QVERIFY(QSettings().fileName().startsWith(m_dir.path()));
    }

    void init() {
        QSettings().clear();
    }

    void plaintextMovesToTheKeyring() {
        writeAccount("a1", "hunter2");
        auto         *store = new FakeSecretStore;
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        QTRY_COMPARE(store->items.value("a1"), QString("hunter2"));
        QTRY_VERIFY(!plaintext("a1").isValid());
        QCOMPARE(QSettings().value("dav/accounts/a1/username").toString(), QString("pat"));
        QCOMPARE(engine.accountCount(), 1);
    }

    void plaintextStaysUntilTheKeyringTakesIt() {
        writeAccount("a1", "hunter2");
        auto *store      = new FakeSecretStore;
        store->available = false;
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        QTest::qWait(200);
        QCOMPARE(engine.accountCount(), 1);
        QCOMPARE(plaintext("a1").toString(), QString("hunter2"));
        store->available = true;
        QTRY_COMPARE_WITH_TIMEOUT(store->items.value("a1"), QString("hunter2"), 5000);
        QTRY_VERIFY(!plaintext("a1").isValid());
    }

    void syncWaitsForTheKeyringSecret() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        writeAccount("a1", {});
        QSettings().setValue(
            "dav/accounts/a1/collectionsContacts",
            QStringList{QString("http://127.0.0.1:%1/c/").arg(server.serverPort())});
        auto *store = new FakeSecretStore;
        store->items.insert("a1", "hunter2");
        store->available = false;
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        QTRY_COMPARE(store->loads.size(), 1);
        engine.syncNow();
        QTest::qWait(200);
        QVERIFY(!server.hasPendingConnections());

        store->available = true;
        QTRY_COMPARE_WITH_TIMEOUT(store->loads.size(), 2, 5000);
        engine.syncNow();
        QTRY_VERIFY(server.hasPendingConnections());
        QTcpSocket *socket = server.nextPendingConnection();
        QTRY_VERIFY(socket->peek(4096).contains("\r\n\r\n"));
        const QByteArray request = socket->readAll();
        QVERIFY(request.contains("Authorization: Basic " + QByteArray("pat:hunter2").toBase64()));
        QCOMPARE(engine.accountCount(), 1);
    }

    void newAccountsNeverTouchSettings() {
        auto         *store = new FakeSecretStore;
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        const QString id =
            engine.addAccount("Fastmail", "https://127.0.0.1:9/", "pat", "app-password");
        QTRY_COMPARE(store->items.value(id), QString("app-password"));
        QVERIFY(!plaintext(id).isValid());
        QCOMPARE(QSettings().value("dav/accounts/" + id + "/username").toString(), QString("pat"));
    }

    void removalDeletesTheItem() {
        writeAccount("a1", {});
        auto *store = new FakeSecretStore;
        store->items.insert("a1", "hunter2");
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        QVERIFY(engine.removeAccount("a1"));
        QTRY_VERIFY(!store->items.contains("a1"));
        QTRY_VERIFY(!QSettings().contains("dav/pendingSecretRemovals"));
    }

    void removalSurvivesARestart() {
        writeAccount("a1", {});
        {
            auto *store      = new FakeSecretStore;
            store->available = false;
            DavSyncEngine engine(nullptr, nullptr, nullptr, store);
            QVERIFY(engine.removeAccount("a1"));
            QTest::qWait(100);
        }
        QCOMPARE(QSettings().value("dav/pendingSecretRemovals").toStringList(), QStringList{"a1"});
        auto *store = new FakeSecretStore;
        store->items.insert("a1", "hunter2");
        DavSyncEngine engine(nullptr, nullptr, nullptr, store);
        QCOMPARE(engine.accountCount(), 0);
        QTRY_VERIFY(!store->items.contains("a1"));
        QTRY_VERIFY(!QSettings().contains("dav/pendingSecretRemovals"));
    }

    void secretServiceRoundTrip() {
        if (QStandardPaths::findExecutable("gnome-keyring-daemon").isEmpty())
            QSKIP("gnome-keyring-daemon not installed");
        KeyringBus kb;
        QVERIFY(kb.start());
        QDBusConnection bus = QDBusConnection::connectToBus(kb.address, "roundtrip");
        QVERIFY(kb.startKeyring(bus));
        SecretServiceStore store(bus);

        Answer             stored;
        store.store("a1", "Marathon DAV · Nextcloud", "hunter2 ✓", stored.callback());
        QTRY_VERIFY(stored.done);
        QCOMPARE(stored.result, DavSecretStore::Result::Ok);

        Answer replaced;
        store.store("a1", "Marathon DAV · Nextcloud", "correct horse", replaced.callback());
        QTRY_VERIFY(replaced.done);
        QCOMPARE(replaced.result, DavSecretStore::Result::Ok);

        Answer loaded;
        store.load("a1", loaded.callback());
        QTRY_VERIFY(loaded.done);
        QCOMPARE(loaded.result, DavSecretStore::Result::Ok);
        QCOMPARE(loaded.secret, QString("correct horse"));

        Answer removed;
        store.remove("a1", removed.callback());
        QTRY_VERIFY(removed.done);
        QCOMPARE(removed.result, DavSecretStore::Result::Ok);

        Answer gone;
        store.load("a1", gone.callback());
        QTRY_VERIFY(gone.done);
        QCOMPARE(gone.result, DavSecretStore::Result::NotFound);
    }

    void secretServiceAbsentIsUnavailable() {
        KeyringBus kb;
        QVERIFY(kb.start());
        SecretServiceStore store(QDBusConnection::connectToBus(kb.address, "absent"));
        Answer             stored;
        store.store("a1", "x", "hunter2", stored.callback());
        QTRY_VERIFY(stored.done);
        QCOMPARE(stored.result, DavSecretStore::Result::Unavailable);
        Answer loaded;
        store.load("a1", loaded.callback());
        QTRY_VERIFY(loaded.done);
        QCOMPARE(loaded.result, DavSecretStore::Result::Unavailable);
    }
};

QTEST_GUILESS_MAIN(TestDavSecrets)
#include "test_davsecrets.moc"
