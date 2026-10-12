#include <QBuffer>
#include <QDataStream>
#include <QtTest>

#include "nemoremoteaction.h"

// Encoded exactly as Nemo.Notifications' encodeDBusCall does.
static QString encode(const QString &call, const QVariantList &args) {
    QString s = call;
    for (const QVariant &arg : args) {
        QByteArray  buffer;
        QDataStream stream(&buffer, QIODevice::WriteOnly);
        stream << arg;
        s += QLatin1Char(' ') + QString::fromLatin1(buffer.toBase64());
    }
    return s;
}

class TestNemoRemoteAction : public QObject {
    Q_OBJECT

  private slots:
    void decodesCallWithArguments() {
        const QString hint = encode(QStringLiteral("org.example.app /app org.example.App openNote"),
                                    {QVariant(42), QVariant(QStringLiteral("draft"))});
        bool         ok    = false;
        const auto   msg   = NemoRemoteAction::decode(hint, &ok);
        QVERIFY(ok);
        QCOMPARE(msg.service(), QString("org.example.app"));
        QCOMPARE(msg.path(), QString("/app"));
        QCOMPARE(msg.interface(), QString("org.example.App"));
        QCOMPARE(msg.member(), QString("openNote"));
        QCOMPARE(msg.arguments().size(), 2);
        QCOMPARE(msg.arguments().at(0).toInt(), 42);
        QCOMPARE(msg.arguments().at(1).toString(), QString("draft"));
    }
    void decodesCallWithoutArguments() {
        bool ok = false;
        QCOMPARE(NemoRemoteAction::decode(QStringLiteral("a.b /c a.B go"), &ok).arguments().size(), 0);
        QVERIFY(ok);
    }
    void rejectsShortHints() {
        bool ok = true;
        NemoRemoteAction::decode(QStringLiteral("a.b /c"), &ok);
        QVERIFY(!ok);
    }
    void hintNameForAction() {
        QCOMPARE(NemoRemoteAction::hintName(QStringLiteral("default")),
                 QString("x-nemo-remote-action-default"));
    }
};

QTEST_GUILESS_MAIN(TestNemoRemoteAction)
#include "test_nemoremoteaction.moc"
