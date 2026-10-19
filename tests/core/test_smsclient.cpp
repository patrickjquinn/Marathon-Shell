#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusUnixFileDescriptor>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>

#include <fcntl.h>
#include <unistd.h>

#include "ipc/shellipcclients.h"
#include "mmspartarg.h"

// The shell's Sms1 and Permissions1, served from their own thread: the
// client's calls block until they are answered.
class FakeSms : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Sms1")

  public:
    QString           attachmentFile;
    QStringList       recipients;
    QString           text;
    QStringList       types;
    QStringList       names;
    QList<QByteArray> contents;

  public slots:
    QVariantList GetConversations() {
        return {};
    }
    bool IsMmsAvailable() {
        return true;
    }
    int SendMms(const QStringList &to, const QString &body, const QList<MmsPartArg> &parts) {
        recipients = to;
        text       = body;
        for (const MmsPartArg &part : parts) {
            types << part.contentType;
            names << part.name;
            QFile file;
            if (file.open(::dup(part.fd.fileDescriptor()), QIODevice::ReadOnly, QFileDevice::AutoCloseHandle))
                contents << file.readAll();
        }
        return 42;
    }
    QDBusUnixFileDescriptor OpenAttachment(int) const {
        const int               fd = ::open(attachmentFile.toLocal8Bit().constData(), O_RDONLY | O_CLOEXEC);
        QDBusUnixFileDescriptor out(fd);
        ::close(fd);
        return out;
    }
};

class FakePermissions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public slots:
    bool HasPermission(const QString &, const QString &) {
        return true;
    }
};

class TestSmsClient : public QObject {
    Q_OBJECT

    QTemporaryDir   dir;
    QThread         thread;
    FakeSms        *sms         = nullptr;
    FakePermissions *permissions = nullptr;

    QString file(const QString &name, const QByteArray &content) {
        QFile f(dir.filePath(name));
        if (f.open(QIODevice::WriteOnly))
            f.write(content);
        return f.fileName();
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        qDBusRegisterMetaType<MmsPartArg>();
        qDBusRegisterMetaType<QList<MmsPartArg>>();
        thread.start();
        auto *home = new QObject;
        home->moveToThread(&thread);
        QMetaObject::invokeMethod(
            home,
            [this]() {
                QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "shell");
                sms                 = new FakeSms;
                permissions         = new FakePermissions;
                bus.registerObject("/org/marathonos/Shell/Sms", sms, QDBusConnection::ExportAllSlots);
                bus.registerObject("/org/marathonos/Shell/Permissions", permissions,
                                   QDBusConnection::ExportAllSlots);
                bus.registerService("org.marathonos.Shell");
            },
            Qt::BlockingQueuedConnection);
    }

    void cleanupTestCase() {
        thread.quit();
        thread.wait();
    }

    // The app opens its own files; only descriptors reach the shell.
    void picturesGoAsDescriptors() {
        SmsClient client(QStringLiteral("messages"));
        QTRY_VERIFY(client.mmsAvailable());
        const QString picture = file("beach.png", "\x89PNG beach");
        const int     id      = client.sendMms({"+15550300"}, "Look",
                                               {QVariantMap{{"contentType", "image/png"}, {"filePath", picture}}});
        QCOMPARE(id, 42);
        QCOMPARE(sms->recipients, QStringList{"+15550300"});
        QCOMPARE(sms->text, QString("Look"));
        QCOMPARE(sms->types, QStringList{"image/png"});
        QCOMPARE(sms->names, QStringList{"beach.png"});
        QCOMPARE(sms->contents, QList<QByteArray>{QByteArray("\x89PNG beach")});
    }

    void aFileThatCannotBeOpenedSendsNothing() {
        SmsClient client(QStringLiteral("messages"));
        sms->recipients.clear();
        QCOMPARE(client.sendMms({"+15550301"}, "x",
                                {QVariantMap{{"contentType", "image/png"}, {"filePath", dir.filePath("missing.png")}}}),
                 -1);
        QVERIFY(sms->recipients.isEmpty());
    }

    // An attachment is copied into the app's cache, where Image can read it.
    void anAttachmentOpensAsACachedFile() {
        sms->attachmentFile = file("stored.jpg", "jpeg bytes");
        SmsClient     client(QStringLiteral("messages"));
        const QString path = client.openAttachment(7, "../photo.jpg");
        QVERIFY(path.startsWith(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)));
        QVERIFY(path.endsWith("/photo.jpg"));
        QFile cached(path);
        QVERIFY(cached.open(QIODevice::ReadOnly));
        QCOMPARE(cached.readAll(), QByteArray("jpeg bytes"));
    }
};

QTEST_GUILESS_MAIN(TestSmsClient)
#include "test_smsclient.moc"
