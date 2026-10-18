#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QDir>
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

    void deleteUnknownIdFails() {
        SMSService sms;
        QVERIFY(!sms.deleteMessage(999999));
    }
};

QTEST_MAIN(TestSmsService)
#include "test_smsservice.moc"
