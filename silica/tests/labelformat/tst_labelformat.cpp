// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Label text format and untrusted strings. Silica's Label uses
// `textFormat: _defaultLabelFormat`, which follows
// ApplicationWindow._defaultLabelFormat (Text.AutoText unless the app sets
// it). An app that shows untrusted strings sets Text.PlainText on the Label
// (or _defaultLabelFormat on its window); then markup such as
// `<img src="http://...">` must not make the engine fetch anything. Requests
// are counted with a QQmlNetworkAccessManagerFactory (remote images) and an
// image provider (image:// URLs). Each case has a rich-text control that
// shows the counters do see a load.

#include <QAtomicInt>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickImageProvider>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

namespace {

QAtomicInt g_networkRequests;
QAtomicInt g_providerRequests;

class CountingNam : public QNetworkAccessManager
{
public:
    using QNetworkAccessManager::QNetworkAccessManager;

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request,
                                 QIODevice *data) override
    {
        g_networkRequests.ref();
        // Never reach the network: point the request at an invalid scheme.
        QNetworkRequest blocked(request);
        blocked.setUrl(QUrl(QStringLiteral("keel-blocked:none")));
        return QNetworkAccessManager::createRequest(op, blocked, data);
    }
};

class CountingNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override { return new CountingNam(parent); }
};

class CountingProvider : public QQuickImageProvider
{
public:
    CountingProvider() : QQuickImageProvider(QQuickImageProvider::Image) { }
    QImage requestImage(const QString &, QSize *size, const QSize &) override
    {
        g_providerRequests.ref();
        QImage image(4, 4, QImage::Format_ARGB32);
        image.fill(Qt::red);
        if (size)
            *size = image.size();
        return image;
    }
};

} // namespace

class tst_LabelFormat : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void plainTextLabelLoadsNothing_data();
    void plainTextLabelLoadsNothing();
    void windowDefaultLabelFormat();

private:
    QObject *load(const QByteArray &qml);

    QScopedPointer<QQmlEngine> m_engine;
    CountingNamFactory m_factory;
    QScopedPointer<QObject> m_root;
};

void tst_LabelFormat::init()
{
    m_root.reset();
    m_engine.reset(new QQmlEngine);
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
    m_engine->setNetworkAccessManagerFactory(&m_factory);
    m_engine->addImageProvider(QStringLiteral("counter"), new CountingProvider);
    g_networkRequests = 0;
    g_providerRequests = 0;
}

QObject *tst_LabelFormat::load(const QByteArray &qml)
{
    QQmlComponent component(m_engine.data());
    component.setData(qml, QUrl(QStringLiteral("file:///keel/tst_labelformat.qml")));
    if (!component.isReady()) {
        qWarning() << component.errors();
        return nullptr;
    }
    m_root.reset(component.create());
    return m_root.data();
}

void tst_LabelFormat::plainTextLabelLoadsNothing_data()
{
    QTest::addColumn<QString>("source");
    QTest::addColumn<bool>("viaNetwork");
    QTest::newRow("remote") << QStringLiteral("http://127.0.0.1:9/tracker.png") << true;
    QTest::newRow("provider") << QStringLiteral("image://counter/tracker") << false;
}

void tst_LabelFormat::plainTextLabelLoadsNothing()
{
    QFETCH(QString, source);
    QFETCH(bool, viaNetwork);
    QAtomicInt &counter = viaNetwork ? g_networkRequests : g_providerRequests;
    const QByteArray markup = QStringLiteral("<b>Hi</b><img src=\"%1\" width=\"4\" height=\"4\">")
                                      .arg(source).toUtf8();

    QObject *root = load("import QtQuick\nimport Sailfish.Silica 1.0\n"
                         "Window { visible: true; width: 200; height: 200\n"
                         "  property alias plain: plain\n"
                         "  Label { id: plain; textFormat: Text.PlainText; text: '"
                         + markup + "' } }\n");
    QVERIFY(root);
    auto *plain = root->property("plain").value<QQuickItem *>();
    QVERIFY(plain);
    QCOMPARE(plain->property("textFormat").toInt(), 0); // Text.PlainText
    QCOMPARE(plain->property("text").toString(), QString::fromUtf8(markup));
    // Give any (wrongly) started load time to reach the counters.
    QTest::qWait(300);
    QCoreApplication::processEvents();
    QCOMPARE(counter.loadAcquire(), 0);

    // Control: the same string in a rich text Label is loaded, so the
    // counter above would have seen a load.
    QObject *rich = load("import QtQuick\nimport Sailfish.Silica 1.0\n"
                         "Window { visible: true; width: 200; height: 200\n"
                         "  Label { textFormat: Text.RichText; text: '" + markup + "' } }\n");
    QVERIFY(rich);
    QTRY_VERIFY(counter.loadAcquire() > 0);
}

void tst_LabelFormat::windowDefaultLabelFormat()
{
    // Label follows the window's _defaultLabelFormat (Silica's mechanism),
    // AutoText by default, PlainText when the app sets it.
    QObject *root = load("import QtQuick\nimport Sailfish.Silica 1.0\n"
                         "ApplicationWindow {\n"
                         "  property Item label: page.label\n"
                         "  _defaultLabelFormat: Text.PlainText\n"
                         "  initialPage: Page { id: page; property alias label: l\n"
                         "    Label { id: l; text: '<img src=\"image://counter/tracker\">' } }\n"
                         "}\n");
    QVERIFY(root);
    QTRY_VERIFY(root->property("label").value<QQuickItem *>());
    auto *label = root->property("label").value<QQuickItem *>();
    QCOMPARE(label->property("textFormat").toInt(), 0); // Text.PlainText
    QTest::qWait(300);
    QCOMPARE(g_providerRequests.loadAcquire(), 0);

    QObject *autoRoot = load("import QtQuick\nimport Sailfish.Silica 1.0\n"
                             "ApplicationWindow {\n"
                             "  property Item label: page.label\n"
                             "  initialPage: Page { id: page; property alias label: l\n"
                             "    Label { id: l; text: 'x' } }\n"
                             "}\n");
    QVERIFY(autoRoot);
    QTRY_VERIFY(autoRoot->property("label").value<QQuickItem *>());
    QCOMPARE(autoRoot->property("label").value<QQuickItem *>()->property("textFormat").toInt(),
             2); // Text.AutoText
}

QTEST_MAIN(tst_LabelFormat)
#include "tst_labelformat.moc"
