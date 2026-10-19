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
#include <QBuffer>
#include <QImage>
#include <QRandomGenerator>
#include <fcntl.h>
#include <unistd.h>

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
        return {{"TotalMaxAttachmentSize", 120000}, {"MaxAttachments", 25}};
    }
    QDBusObjectPath SendMessage(const QStringList &to, const QDBusVariant &, const QList<FakeSent> &list) {
        recipients = to;
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

    static int fdOf(const QString &path) {
        return ::open(path.toLocal8Bit().constData(), O_RDONLY | O_CLOEXEC);
    }

    void emitStatus(const QString &path, const QString &status) {
        QDBusMessage changed =
            QDBusMessage::createSignal(path, "org.ofono.mms.Message", "PropertyChanged");
        changed << QString("Status") << QVariant::fromValue(QDBusVariant(status));
        QVERIFY(mmsd.send(changed));
    }

    // A message that needs MMS goes to mmsd-tng with its text first; its
    // status follows mmsd-tng's.
    void aPictureIsSentThroughMmsd() {
        SMSService sms;
        MmsManager mms;
        QTRY_VERIFY(mms.available());
        sms.setMmsManager(&mms);
        QSignalSpy status(&sms, &SMSService::messageStatusChanged);
        service.sentParts.clear();
        service.sentTypes.clear();

        QFile picture(store.filePath("small.png"));
        QVERIFY(picture.open(QIODevice::WriteOnly));
        QImage(8, 8, QImage::Format_RGB32).save(&picture, "PNG");
        picture.close();
        const int fd = fdOf(picture.fileName());
        const int id = sms.sendMms({"+15550200"}, "Here", {{"image/png", "small.png", fd}});
        ::close(fd);
        QVERIFY(id > 0);
        QTRY_COMPARE(service.sentParts.size(), 2);
        QCOMPARE(service.recipients, QStringList{"+15550200"});
        QCOMPARE(service.sentParts.at(0), QByteArray("Here"));
        QCOMPARE(service.sentTypes.at(1), QString("image/png"));
        QFile original(picture.fileName());
        QVERIFY(original.open(QIODevice::ReadOnly));
        QCOMPARE(service.sentParts.at(1), original.readAll());

        const auto message = [&sms]() {
            return sms.getMessages(sms.generateConversationId("+15550200")).constLast().toMap();
        };
        QCOMPARE(message().value("status").toString(), QString("sending"));
        QCOMPARE(message().value("attachments").toList().size(), 1);
        emitStatus(QStringLiteral("/org/ofono/mms/modemmanager/message%1").arg(service.sent), "sent");
        QTRY_COMPARE(message().value("status").toString(), QString("sent"));
        QCOMPARE(status.constLast().at(0).toInt(), id);
        QCOMPARE(status.constLast().at(1).toString(), QString("sent"));
    }

    void aSendErrorFailsTheMessage() {
        SMSService sms;
        MmsManager mms;
        QTRY_VERIFY(mms.available());
        sms.setMmsManager(&mms);
        QSignalSpy status(&sms, &SMSService::messageStatusChanged);
        const int  sentBefore = service.sent;
        const int  id         = sms.sendMms({"+15550201", "+15550202"}, "Both of you", {});
        QTRY_COMPARE(service.sent, sentBefore + 1);
                QDBusMessage error = QDBusMessage::createSignal("/org/ofono/mms/modemmanager",
                                                        "org.ofono.mms.Service", "MessageSendError");
        error << QVariantMap{{"ErrorType", 2u},
                             {"Host", "mmsc.example"},
                             {"MessagePath", QStringLiteral("/org/ofono/mms/modemmanager/message%1").arg(service.sent)}};
        QVERIFY(mmsd.send(error));
        QTRY_VERIFY(!status.isEmpty() && status.constLast().at(1).toString() == "failed");
        QCOMPARE(status.constLast().at(0).toInt(), id);
    }

    // Never sent as SMS instead: without mmsd-tng the message fails.
    void withoutMmsdItFails() {
        SMSService sms;
        QSignalSpy failed(&sms, &SMSService::sendFailed);
        const int  id = sms.sendMms({"+15550203"}, "Picture", {});
        QVERIFY(id > 0);
        QCOMPARE(failed.size(), 1);
        QCOMPARE(sms.getMessages(sms.generateConversationId("+15550203")).constLast().toMap().value("status").toString(),
                 QString("failed"));
    }

    // A photo over the carrier's limit is scaled down to fit.
    void aBigPhotoIsScaledDown() {
        SMSService sms;
        MmsManager mms;
        QTRY_VERIFY(mms.available());
        QTRY_COMPARE(mms.maxAttachmentSize(), qint64(120000));
        sms.setMmsManager(&mms);
        service.sentParts.clear();
        service.sentTypes.clear();

        QImage photo(1600, 1200, QImage::Format_RGB32);
        for (int y = 0; y < photo.height(); ++y)
            for (int x = 0; x < photo.width(); ++x)
                photo.setPixel(x, y, QRandomGenerator::global()->generate());
        QFile big(store.filePath("big.png"));
        QVERIFY(big.open(QIODevice::WriteOnly));
        photo.save(&big, "PNG");
        big.close();
        QVERIFY(big.size() > 120000);

        const int fd = fdOf(big.fileName());
        sms.sendMms({"+15550204"}, QString(), {{"image/png", "big.png", fd}});
        ::close(fd);
        QTRY_COMPARE(service.sentParts.size(), 1);
        QCOMPARE(service.sentTypes.at(0), QString("image/jpeg"));
        QVERIFY(service.sentParts.at(0).size() <= 120000);
        QImage sent;
        QVERIFY(sent.loadFromData(service.sentParts.at(0)));
        QVERIFY(sent.width() < 1600);
        QCOMPARE(sent.width() * 3, sent.height() * 4);
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
