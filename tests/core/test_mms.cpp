#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include "mmsmanager.h"
#include "smsservice.h"

// mmsd-tng's attachment as it lists them: (id, content type, stored file,
// offset, length).
struct FakeStored {
    QString id;
    QString type;
    QString file;
    quint64 offset = 0;
    quint64 length = 0;
};
Q_DECLARE_METATYPE(FakeStored)
QDBusArgument &operator<<(QDBusArgument &arg, const FakeStored &a) {
    arg.beginStructure();
    arg << a.id << a.type << a.file << a.offset << a.length;
    arg.endStructure();
    return arg;
}
const QDBusArgument &operator>>(const QDBusArgument &arg, FakeStored &a) {
    arg.beginStructure();
    arg >> a.id >> a.type >> a.file >> a.offset >> a.length;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

// What SendMessage is given per attachment: (id, content type, file).
struct FakeSent {
    QString id;
    QString type;
    QString file;
};
Q_DECLARE_METATYPE(FakeSent)
QDBusArgument &operator<<(QDBusArgument &arg, const FakeSent &a) {
    arg.beginStructure();
    arg << a.id << a.type << a.file;
    arg.endStructure();
    return arg;
}
const QDBusArgument &operator>>(const QDBusArgument &arg, FakeSent &a) {
    arg.beginStructure();
    arg >> a.id >> a.type >> a.file;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

using ServiceEntry = QPair<QDBusObjectPath, QVariantMap>;
using ServiceList  = QList<ServiceEntry>;
Q_DECLARE_METATYPE(ServiceEntry)
Q_DECLARE_METATYPE(ServiceList)

class FakeManager : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.ofono.mms.Manager")

  public slots:
    ServiceList GetServices() {
        return {{QDBusObjectPath("/org/ofono/mms/modemmanager"), {}}};
    }
};

class FakeService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.ofono.mms.Service")

  public:
    QStringList        recipients;
    QList<QByteArray>  sentParts;
    QStringList        sentTypes;
    int                sent = 0;

  public slots:
    QVariantMap GetProperties() {
        return {{"TotalMaxAttachmentSize", 1100000}, {"MaxAttachments", 25}};
    }
    QDBusObjectPath SendMessage(const QStringList &to, const QDBusVariant &, const QDBusArgument &atts) {
        recipients = to;
        QList<FakeSent> list;
        atts >> list;
        for (const FakeSent &a : std::as_const(list)) {
            QFile f(a.file);
            sentParts << (f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray());
            sentTypes << a.type;
        }
        return QDBusObjectPath(QStringLiteral("/org/ofono/mms/modemmanager/message%1").arg(++sent));
    }
};

class TestMms : public QObject {
    Q_OBJECT

    QTemporaryDir   store;
    QDBusConnection mmsd = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "mmsd");
    FakeManager     manager;
    FakeService     service;

    void emitAdded(const QString &path, const QVariantMap &props) {
        QDBusMessage added = QDBusMessage::createSignal("/org/ofono/mms/modemmanager",
                                                        "org.ofono.mms.Service", "MessageAdded");
        added << QVariant::fromValue(QDBusObjectPath(path)) << props;
        QVERIFY(mmsd.send(added));
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).removeRecursively();
        qDBusRegisterMetaType<FakeStored>();
        qDBusRegisterMetaType<QList<FakeStored>>();
        qDBusRegisterMetaType<FakeSent>();
        qDBusRegisterMetaType<QList<FakeSent>>();
        qDBusRegisterMetaType<ServiceEntry>();
        qDBusRegisterMetaType<ServiceList>();
        QVERIFY(mmsd.registerObject("/org/ofono/mms", &manager, QDBusConnection::ExportAllSlots));
        QVERIFY(mmsd.registerObject("/org/ofono/mms/modemmanager", &service,
                                    QDBusConnection::ExportAllSlots));
        QVERIFY(mmsd.registerService("org.ofono.mms"));
    }

    // mmsd-tng keeps a received MMS in one file; each part is a slice of it.
    void aReceivedPictureIsKept() {
        const QByteArray text  = "Look at this";
        const QByteArray image = "\x89PNG picture bytes";
        QFile            file(store.filePath("message1"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("header" + text + image);
        file.close();

        SMSService sms;
        MmsManager mms;
        QTRY_VERIFY(mms.available());
        sms.setMmsManager(&mms);
        QSignalSpy received(&sms, &SMSService::messageReceived);

        const QList<FakeStored> parts{
            {"text.txt", "text/plain;charset=utf-8", file.fileName(), 6, quint64(text.size())},
            {"beach.png", "image/png", file.fileName(), quint64(6 + text.size()), quint64(image.size())}};
        emitAdded("/org/ofono/mms/modemmanager/message9",
                  {{"Status", "received"},
                   {"Date", "2026-10-19T10:00:00+0100"},
                   {"Sender", "+15550100"},
                   {"Recipients", QStringList{"+15550199"}},
                   {"Attachments", QVariant::fromValue(parts)}});
        QTRY_COMPARE(received.size(), 1);

        const QVariantList messages = sms.getMessages(sms.generateConversationId("+15550100"));
        QCOMPARE(messages.size(), 1);
        const QVariantMap message = messages.first().toMap();
        QCOMPARE(message.value("text").toString(), QString("Look at this"));
        QCOMPARE(message.value("status").toString(), QString("received"));
        const QVariantList atts = message.value("attachments").toList();
        QCOMPARE(atts.size(), 1);
        QCOMPARE(atts.first().toMap().value("contentType").toString(), QString("image/png"));
        QCOMPARE(atts.first().toMap().value("name").toString(), QString("beach.png"));
        QFile stored(sms.attachmentPath(atts.first().toMap().value("id").toInt()));
        QVERIFY(stored.open(QIODevice::ReadOnly));
        QCOMPARE(stored.readAll(), image);
    }
};

QTEST_GUILESS_MAIN(TestMms)
#include "test_mms.moc"
