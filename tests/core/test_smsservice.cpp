#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryFile>
#include <fcntl.h>
#include <unistd.h>
#include "smsservice.h"

class TestSmsService : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).removeRecursively();
    }

    void deleteMessageRemovesOnlyThatMessage() {
        SMSService sms;
        sms.simulateIncomingSMS("+15551234567", "first");
        sms.simulateIncomingSMS("+15551234567", "second");
        const QString      conv     = sms.generateConversationId("+15551234567");
        const QVariantList messages = sms.getMessages(conv);
        QCOMPARE(messages.size(), 2);

        QSignalSpy changed(&sms, &SMSService::conversationsChanged);
        QVERIFY(sms.deleteMessage(messages.first().toMap().value("id").toInt()));
        QCOMPARE(changed.count(), 1);

        const QVariantList left = sms.getMessages(conv);
        QCOMPARE(left.size(), 1);
        QCOMPARE(left.first().toMap().value("text").toString(), QString("second"));
        QCOMPARE(sms.conversations().constFirst().toMap().value("lastMessage").toString(),
                 QString("second"));
    }

    void deletingLastMessageDropsConversation() {
        SMSService sms;
        sms.simulateIncomingSMS("+447700900123", "only");
        const QString conv = sms.generateConversationId("+447700900123");
        const int     id   = sms.getMessages(conv).constFirst().toMap().value("id").toInt();
        QVERIFY(sms.deleteMessage(id));
        const QVariantList conversations = sms.conversations();
        for (const QVariant &c : conversations)
            QVERIFY(c.toMap().value("id").toString() != conv);
    }

    // A messages.db from before MMS: its rows get a status, and it can hold
    // attachments.
    void anOldDatabaseIsMigrated() {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir(dir).removeRecursively();
        QVERIFY(QDir().mkpath(dir));
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "old");
            db.setDatabaseName(dir + "/messages.db");
            QVERIFY(db.open());
            QSqlQuery q(db);
            QVERIFY(q.exec("CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, conversationId "
                           "TEXT NOT NULL, sender TEXT NOT NULL, recipient TEXT NOT NULL, text TEXT NOT "
                           "NULL, timestamp INTEGER NOT NULL, isRead INTEGER DEFAULT 0, isOutgoing "
                           "INTEGER DEFAULT 0)"));
            QVERIFY(q.exec("INSERT INTO messages (conversationId, sender, recipient, text, timestamp, "
                           "isOutgoing) VALUES ('+15550001', '+15550001', 'me', 'in', 1, 0)"));
            QVERIFY(q.exec("INSERT INTO messages (conversationId, sender, recipient, text, timestamp, "
                           "isOutgoing) VALUES ('+15550001', 'me', '+15550001', 'out', 2, 1)"));
            db.close();
        }
        QSqlDatabase::removeDatabase("old");

        SMSService         sms;
        const QVariantList messages = sms.getMessages("+15550001");
        QCOMPARE(messages.size(), 2);
        QCOMPARE(messages.at(0).toMap().value("status").toString(), QString("received"));
        QCOMPARE(messages.at(1).toMap().value("status").toString(), QString("sent"));
        QCOMPARE(messages.at(0).toMap().value("attachments").toList().size(), 0);
    }

    void anAttachmentIsStoredAndGoesWithItsMessage() {
        SMSService sms;
        sms.simulateIncomingSMS("+15550002", "photo");
        const int id = sms.getMessages("+15550002").constFirst().toMap().value("id").toInt();

        QTemporaryFile source;
        QVERIFY(source.open());
        source.write("\x89PNG data");
        source.flush();
        const int fd = ::open(source.fileName().toLocal8Bit().constData(), O_RDONLY | O_CLOEXEC);
        const int attachment = sms.addAttachment(id, "image/png", "../../beach.png", fd);
        ::close(fd);
        QVERIFY(attachment > 0);

        const QVariantList atts =
            sms.getMessages("+15550002").constFirst().toMap().value("attachments").toList();
        QCOMPARE(atts.size(), 1);
        QCOMPARE(atts.at(0).toMap().value("contentType").toString(), QString("image/png"));
        QCOMPARE(atts.at(0).toMap().value("name").toString(), QString("beach.png"));
        QCOMPARE(atts.at(0).toMap().value("size").toLongLong(), qint64(9));

        const QString path = sms.attachmentPath(attachment);
        QVERIFY(path.startsWith(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) +
                                "/marathon/mms/"));
        QFile stored(path);
        QVERIFY(stored.open(QIODevice::ReadOnly));
        QCOMPARE(stored.readAll(), QByteArray("\x89PNG data"));

        QVERIFY(sms.deleteMessage(id));
        QVERIFY(!QFile::exists(path));
        QVERIFY(sms.attachmentPath(attachment).isEmpty());
    }

    void deleteUnknownIdFails() {
        SMSService sms;
        QVERIFY(!sms.deleteMessage(999999));
    }
};

QTEST_MAIN(TestSmsService)
#include "test_smsservice.moc"
