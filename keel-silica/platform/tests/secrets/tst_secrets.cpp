// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Qt 6 build of the sailfish-secrets client against a fake
// sailfishsecretsd (run under dbus-run-session):
//
//  - the fake answers the discovery calls on the session bus and serves
//    /Sailfish/Crypto and /Sailfish/Secrets on its own peer-to-peer
//    QDBusServer, as the daemon does (daemon/controller.cpp);
//  - it checks each call's D-Bus signature against the daemon's
//    introspection data (daemon/CryptoImpl/crypto_p.h and
//    daemon/SecretsImpl/secrets_p.h of sailfish-secrets 5a8d33e, BSD-3-Clause,
//    the strings below are copied from there) and builds its replies with
//    plain QDBusArgument calls, not with the library's marshalling;
//  - the QML side is used as sfos-forum-viewer's LoginPage.qml uses it
//    (GenerateKeyRequest, DecryptRequest, CryptoManager helpers).
// Also: a key serialised by the same upstream code built with Qt 5.15
// (daemon side) must read back identically in the Qt 6 build.

#include "Crypto/key.h"
#include "Crypto/cryptomanager.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusServer>
#include <QDBusVirtualObject>
#include <QGuiApplication>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSemaphore>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>
#include <memory>

using Sailfish::Crypto::CryptoManager;
using Sailfish::Crypto::Key;

namespace {

// Key::serialize() of the key in keySerialization(), printed by the
// upstream lib/Crypto sources (5a8d33e) built with Qt 5.15.13 on the host.
const char kQt5KeyHex[]
    = "4b657900000000640000000a006d0079004b006500790000000e006d007900470072006f007500700000002a0070006c007500"
      "670069006e002e00630072007900700074006f002e00640065006600610075006c0074000000020000000a0000001800000003"
      "000008000000000a5055424c4943004b45590000000470726976ffffffff000000020000000161000000026263000000020000"
      "000200780000000200ff0000000800540079007000650000001200430072007900700074006f004b00650079";

// The same key as this Qt 6 build writes it: identical but for the order of
// the two filter-data entries (Qt 5 streams a QMap from its last entry, Qt
// 6 from its first). Fed to the Qt 5 build of upstream's Key::deserialize()
// on 2026-10-01, it read back as the same key.
const char kQt6KeyHex[]
    = "4b657900000000640000000a006d0079004b006500790000000e006d007900470072006f007500700000002a0070006c007500"
      "670069006e002e00630072007900700074006f002e00640065006600610075006c0074000000020000000a0000001800000003"
      "000008000000000a5055424c4943004b45590000000470726976ffffffff000000020000000161000000026263000000020000"
      "000800540079007000650000001200430072007900700074006f004b006500790000000200780000000200ff";

// The daemon's D-Bus API, from its introspection data.
const QString kGenerateKeyIn = QStringLiteral("((sss)iiiiiayayayaay(a{sv}))(ia{sv}a{sv})(ayay(i)(i)(i)(i)xiiia{sv})a{sv}s");
const QString kDecryptIn = QStringLiteral("ayay((sss)iiiiiayayayaay(a{sv}))(i)(i)ayaya{sv}s");
const QString kCollectionNamesIn = QStringLiteral("s");

const char kCryptoXml[] = R"XML(  <interface name="org.sailfishos.crypto">
      <method name="generateKey">
          <arg name="keyTemplate" type="((sss)iiiiiayayayaay(a{sv}))" direction="in" />
          <arg name="kpgParameters" type="(ia{sv}a{sv})" direction="in" />
          <arg name="skdfParameters" type="(ayay(i)(i)(i)(i)xiiia{sv})" direction="in" />
          <arg name="customParameters" type="a{sv}" direction="in" />
          <arg name="cryptosystemProviderName" type="s" direction="in" />
          <arg name="result" type="(iiis)" direction="out" />
          <arg name="key" type="((sss)iiiiiayayayaay(a{sv}))" direction="out" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In0" value="Sailfish::Crypto::Key" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In1" value="Sailfish::Crypto::KeyPairGenerationParameters" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In2" value="Sailfish::Crypto::KeyDerivationParameters" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.Out0" value="Sailfish::Crypto::Result" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.Out1" value="Sailfish::Crypto::Key" />
      </method>
      <method name="decrypt">
          <arg name="data" type="ay" direction="in" />
          <arg name="iv" type="ay" direction="in" />
          <arg name="key" type="((sss)iiiiiayayayaay(a{sv}))" direction="in" />
          <arg name="blockMode" type="(i)" direction="in" />
          <arg name="padding" type="(i)" direction="in" />
          <arg name="authenticationData" type="ay" direction="in" />
          <arg name="authenticationTag" type="ay" direction="in" />
          <arg name="customParameters" type="a{sv}" direction="in" />
          <arg name="cryptosystemProviderName" type="s" direction="in" />
          <arg name="result" type="(iiis)" direction="out" />
          <arg name="decrypted" type="ay" direction="out" />
          <arg name="verificationStatus" type="(i)" direction="out" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In2" value="Sailfish::Crypto::Key" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In3" value="Sailfish::Crypto::CryptoManager::BlockMode" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.In4" value="Sailfish::Crypto::CryptoManager::EncryptionPadding" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.Out0" value="Sailfish::Crypto::Result" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.Out1" value="Sailfish::Crypto::CryptoManager::VerificationStatus" />
      </method>
  </interface>
)XML";

const char kSecretsXml[] = R"XML(  <interface name="org.sailfishos.secrets">
      <method name="collectionNames">
          <arg name="storagePluginName" type="s" direction="in" />
          <arg name="result" type="(iis)" direction="out" />
          <arg name="names" type="a{sb}" direction="out" />
          <annotation name="org.qtproject.QtDBus.QtTypeName.Out0" value="Sailfish::Secrets::Result" />
      </method>
  </interface>
)XML";

const char kPeerXml[] = R"XML(  <interface name="%1">
      <method name="peerToPeerAddress">
          <arg name="address" type="s" direction="out" />
      </method>
  </interface>
)XML";

QVariant structOf(const std::function<void(QDBusArgument &)> &fill)
{
    QDBusArgument a;
    a.beginStructure();
    fill(a);
    a.endStructure();
    return QVariant::fromValue(a);
}

struct Recorded
{
    QString member;
    QString signature;
    QString keyName;
    QByteArray data;
};

class FakeObject : public QDBusVirtualObject
{
public:
    FakeObject(QString xml, std::function<QDBusMessage(const QDBusMessage &)> respond)
        : m_xml(std::move(xml))
        , m_respond(std::move(respond))
    {
    }
    QString introspect(const QString &) const override { return m_xml; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() == QLatin1String("org.freedesktop.DBus.Introspectable"))
            return false;
        connection.send(m_respond(message));
        return true;
    }

private:
    QString m_xml;
    std::function<QDBusMessage(const QDBusMessage &)> m_respond;
};

// The fake daemon, on its own thread.
class FakeDaemon : public QObject
{
public:
    explicit FakeDaemon(const QString &socketDir)
    {
        m_thread.start();
        moveToThread(&m_thread);
        QSemaphore done;
        QMetaObject::invokeMethod(
            this,
            [this, socketDir, &done]() {
                start(socketDir);
                done.release();
            },
            Qt::QueuedConnection);
        done.acquire();
    }
    ~FakeDaemon() override
    {
        QMetaObject::invokeMethod(
            this,
            [this]() {
                QDBusConnection::disconnectFromBus(QStringLiteral("fake-discovery"));
                delete m_server;
                m_objects.clear();
            },
            Qt::BlockingQueuedConnection);
        m_thread.quit();
        m_thread.wait();
    }

    bool ready = false;
    QString address;
    QList<Recorded> calls() const
    {
        QMutexLocker l(&m_mutex);
        return m_calls;
    }

private:
    void record(const Recorded &r)
    {
        QMutexLocker l(&m_mutex);
        m_calls.append(r);
    }

    static QVariant cryptoResult(int code, const QString &message = QString())
    {
        return structOf([&](QDBusArgument &a) { a << code << 0 << 0 << message; });
    }

    QDBusMessage crypto(const QDBusMessage &m)
    {
        Recorded r { m.member(), m.signature(), {}, {} };
        if (m.member() == QLatin1String("generateKey")) {
            const auto tmpl = qvariant_cast<QDBusArgument>(m.arguments().value(0));
            QString name, collection, plugin;
            tmpl.beginStructure();
            tmpl.beginStructure();
            tmpl >> name >> collection >> plugin;
            tmpl.endStructure();
            r.keyName = name;
            record(r);
            if (m.signature() != kGenerateKeyIn)
                return m.createErrorReply(QDBusError::InvalidSignature, m.signature());
            QDBusMessage reply = m.createReply();
            reply << cryptoResult(0 /* Result::Succeeded */);
            reply << structOf([&](QDBusArgument &a) {
                a.beginStructure();
                a << name << collection << plugin;
                a.endStructure();
                a << static_cast<int>(Key::OriginDevice) << static_cast<int>(CryptoManager::AlgorithmRsa)
                  << static_cast<int>(CryptoManager::OperationEncrypt | CryptoManager::OperationDecrypt)
                  << static_cast<int>(Key::MetaData | Key::PublicKeyData) << 2048;
                a << QByteArray("-----BEGIN PUBLIC KEY-----fake") << QByteArray("private") << QByteArray();
                a << QList<QByteArray>();
                a.beginStructure();
                a << QVariantMap { { QStringLiteral("Type"), QStringLiteral("CryptoKey") } };
                a.endStructure();
            });
            return reply;
        }
        if (m.member() == QLatin1String("decrypt")) {
            const auto key = qvariant_cast<QDBusArgument>(m.arguments().value(2));
            QString name, collection, plugin;
            key.beginStructure();
            key.beginStructure();
            key >> name >> collection >> plugin;
            key.endStructure();
            r.keyName = name;
            r.data = m.arguments().value(0).toByteArray();
            record(r);
            if (m.signature() != kDecryptIn)
                return m.createErrorReply(QDBusError::InvalidSignature, m.signature());
            QDBusMessage reply = m.createReply();
            reply << cryptoResult(0) << QByteArray(R"({"key":"api-key-1"})")
                  << structOf([](QDBusArgument &a) { a << 0; });
            return reply;
        }
        record(r);
        return m.createErrorReply(QDBusError::UnknownMethod, m.member());
    }

    QDBusMessage secrets(const QDBusMessage &m)
    {
        record({ m.member(), m.signature(), m.arguments().value(0).toString(), {} });
        if (m.member() == QLatin1String("collectionNames") && m.signature() == kCollectionNamesIn) {
            QDBusMessage reply = m.createReply();
            QDBusArgument names;
            names.beginMap(QMetaType::fromType<QString>(), QMetaType::fromType<bool>());
            for (const auto &[name, locked] : { std::pair { QStringLiteral("forum"), false },
                                                std::pair { QStringLiteral("wallet"), true } }) {
                names.beginMapEntry();
                names << name << locked;
                names.endMapEntry();
            }
            names.endMap();
            reply << structOf([](QDBusArgument &a) { a << 0 /* Succeeded */ << 0 << QString(); }) << QVariant::fromValue(names);
            return reply;
        }
        return m.createErrorReply(QDBusError::UnknownMethod, m.member());
    }

    void start(const QString &socketDir)
    {
        m_server = new QDBusServer(QStringLiteral("unix:path=") + socketDir + QStringLiteral("/p2pSocket"));
        address = m_server->address();
        m_server->setAnonymousAuthenticationAllowed(false);
        connect(m_server, &QDBusServer::newConnection, this, [this](const QDBusConnection &c) {
            QDBusConnection conn(c);
            auto crypto = std::make_shared<FakeObject>(QLatin1String(kCryptoXml),
                                                       [this](const QDBusMessage &m) { return this->crypto(m); });
            auto sec = std::make_shared<FakeObject>(QLatin1String(kSecretsXml),
                                                    [this](const QDBusMessage &m) { return this->secrets(m); });
            conn.registerVirtualObject(QStringLiteral("/Sailfish/Crypto"), crypto.get());
            conn.registerVirtualObject(QStringLiteral("/Sailfish/Secrets"), sec.get());
            m_objects << crypto << sec;
        });
        QDBusConnection session = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                                QStringLiteral("fake-discovery"));
        bool ok = m_server->isConnected() && session.isConnected();
        for (const auto &[service, path] : { std::pair { QStringLiteral("org.sailfishos.crypto.daemon.discovery"),
                                                         QStringLiteral("/Sailfish/Crypto/Discovery") },
                                             std::pair { QStringLiteral("org.sailfishos.secrets.daemon.discovery"),
                                                         QStringLiteral("/Sailfish/Secrets/Discovery") } }) {
            auto discovery = std::make_shared<FakeObject>(
                QString::fromLatin1(kPeerXml).arg(service), [this](const QDBusMessage &m) {
                    return m.member() == QLatin1String("peerToPeerAddress")
                        ? m.createReply(address)
                        : m.createErrorReply(QDBusError::UnknownMethod, m.member());
                });
            ok = ok && session.registerVirtualObject(path, discovery.get()) && session.registerService(service);
            m_objects << discovery;
        }
        ready = ok;
    }

    QThread m_thread;
    QDBusServer *m_server = nullptr;
    QList<std::shared_ptr<FakeObject>> m_objects;
    mutable QMutex m_mutex;
    QList<Recorded> m_calls;
};

} // namespace

class tst_Secrets : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void keySerialization();
    void cryptoThroughQml();
    void secretsThroughQml();

private:
    QTemporaryDir m_runtime;
    std::unique_ptr<FakeDaemon> m_daemon;
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Secrets::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    QVERIFY(m_runtime.isValid());
    m_daemon = std::make_unique<FakeDaemon>(m_runtime.path());
    QVERIFY(m_daemon->ready);
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_Secrets::cleanupTestCase()
{
    m_engine.reset();
    m_daemon.reset();
}

void tst_Secrets::keySerialization()
{
    Key k;
    k.setIdentifier(Key::Identifier(QStringLiteral("myKey"), QStringLiteral("myGroup"),
                                    QStringLiteral("plugin.crypto.default")));
    k.setOrigin(Key::OriginDevice);
    k.setAlgorithm(CryptoManager::AlgorithmRsa);
    k.setOperations(CryptoManager::OperationEncrypt | CryptoManager::OperationDecrypt);
    k.setComponentConstraints(Key::MetaData | Key::PublicKeyData);
    k.setSize(2048);
    k.setPublicKey(QByteArray("PUBLIC\x00KEY", 10));
    k.setPrivateKey(QByteArray("priv"));
    k.setSecretKey(QByteArray());
    k.setCustomParameters(QVector<QByteArray> { "a", "bc" });
    Key::FilterData fd;
    fd.insert(QStringLiteral("Type"), QStringLiteral("CryptoKey"));
    fd.insert(QStringLiteral("x"), QStringLiteral("ÿ"));
    k.setFilterData(fd);

    // What the Qt 5 daemon wrote reads back as the same key here...
    bool ok = false;
    const Key fromQt5 = Key::deserialize(QByteArray::fromHex(kQt5KeyHex), &ok);
    QVERIFY(ok);
    QVERIFY(fromQt5 == k);
    // ...and this build writes the bytes the Qt 5 code was checked to read.
    const QByteArray written = Key::serialize(k, Key::LosslessSerializationMode);
    QCOMPARE(written.toHex(), QByteArray(kQt6KeyHex));
    QVERIFY(Key::deserialize(written, &ok) == k);
    QVERIFY(ok);
    // Same length and bytes up to the filter data.
    const QByteArray qt5 = QByteArray::fromHex(kQt5KeyHex);
    QCOMPARE(written.size(), qt5.size());
    const qsizetype filterAt = qt5.indexOf(QByteArray::fromHex("0000000200000002")) + 4;
    QCOMPARE(written.left(filterAt), qt5.left(filterAt));
}

void tst_Secrets::cryptoThroughQml()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(
import QtQuick 2.0
import Sailfish.Secrets 1.0 as Secrets
import Sailfish.Crypto 1.0 as Crypto
Item {
    property alias gkr: gkr
    property alias dr: dr
    property string pubkey
    property string decrypted
    property var log: []
    Crypto.CryptoManager { id: crypto }
    Crypto.GenerateKeyRequest {
        id: gkr
        manager: crypto
        cryptoPluginName: crypto.defaultCryptoPluginName
        keyTemplate: {
            var key = crypto.constructKey("myKey", "myGroup", crypto.defaultCryptoPluginName)
            key.algorithm = Crypto.CryptoManager.AlgorithmRsa
            key.operations = Crypto.CryptoManager.OperationEncrypt | Crypto.CryptoManager.OperationDecrypt
            return key
        }
        keyPairGenerationParameters: crypto.constructRsaKeygenParams({"modulusLength": 2048, "numberPrimes": 2, "publicExponent": 65537});
        onResultChanged: {
            if (result.code == Crypto.Result.Failed) {
                log.push("GKR failed: " + result.errorMessage)
            } else if (result.code == Crypto.Result.Succeeded) {
                pubkey = gkr.generatedKey.publicKey
                // The app decrypts later (after its web login); upstream
                // emits resultChanged before generatedKeyChanged.
                Qt.callLater(function() {
                    dr.data = "ciphertext"
                    dr.startRequest()
                })
            }
        }
    }
    Crypto.DecryptRequest {
        id: dr
        manager: crypto
        cryptoPluginName: crypto.defaultCryptoPluginName
        key: gkr.generatedKey
        blockMode: Crypto.CryptoManager.BlockModeUnknown
        padding: Crypto.CryptoManager.EncryptionPaddingRsaPkcs1
        onResultChanged: {
            if (result.code == Crypto.Result.Failed)
                log.push("DR failed: " + result.errorMessage)
            else if (result.code == Crypto.Result.Succeeded)
                decrypted = dr.plaintext
        }
    }
}
)QML",
              QUrl(QStringLiteral("login.qml")));
    std::unique_ptr<QObject> page(c.create());
    QVERIFY2(page, qPrintable(c.errorString()));
    auto *gkr = page->property("gkr").value<QObject *>();
    QVERIFY(QMetaObject::invokeMethod(gkr, "startRequest"));
    QTRY_VERIFY_WITH_TIMEOUT(!page->property("decrypted").toString().isEmpty()
                                 || !page->property("log").toList().isEmpty(),
                             10000);
    QCOMPARE(page->property("log").toList(), QVariantList());
    QCOMPARE(page->property("pubkey").toString(), QStringLiteral("-----BEGIN PUBLIC KEY-----fake"));
    QCOMPARE(page->property("decrypted").toString(), QStringLiteral(R"({"key":"api-key-1"})"));

    const QList<Recorded> calls = m_daemon->calls();
    QCOMPARE(calls.size(), 2);
    QCOMPARE(calls.at(0).member, QStringLiteral("generateKey"));
    QCOMPARE(calls.at(0).signature, kGenerateKeyIn);
    QCOMPARE(calls.at(0).keyName, QStringLiteral("myKey"));
    QCOMPARE(calls.at(1).member, QStringLiteral("decrypt"));
    QCOMPARE(calls.at(1).signature, kDecryptIn);
    QCOMPARE(calls.at(1).keyName, QStringLiteral("myKey"));
    QCOMPARE(calls.at(1).data, QByteArray("ciphertext"));
}

void tst_Secrets::secretsThroughQml()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(
import QtQuick 2.0
import Sailfish.Secrets 1.0
Item {
    property alias request: req
    property var names: []
    SecretManager { id: manager }
    CollectionNamesRequest {
        id: req
        manager: manager
        storagePluginName: manager.defaultEncryptedStoragePluginName
        onResultChanged: if (result.code === Result.Succeeded) names = collectionNames
    }
}
)QML",
              QUrl(QStringLiteral("secrets.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QVERIFY(QMetaObject::invokeMethod(o->property("request").value<QObject *>(), "startRequest"));
    QTRY_COMPARE_WITH_TIMEOUT(o->property("names").toStringList(),
                              (QStringList { QStringLiteral("forum"), QStringLiteral("wallet") }), 10000);
    const QList<Recorded> calls = m_daemon->calls();
    QCOMPARE(calls.last().member, QStringLiteral("collectionNames"));
    QCOMPARE(calls.last().keyName, QStringLiteral("plugin.encryptedstorage.default"));
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    tst_Secrets test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_secrets.moc"
