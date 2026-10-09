// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView over the real Qt WebEngine (Chromium, offscreen, no
// sandbox), against a local HTTP server: the WebEngineSettings Keel applies
// through Keel.WebEngine's ProfilePolicy reach the network and the page.
//   cookieBehavior  BlockThirdParty keeps 127.0.0.1's (first-party) cookie
//                   and drops localhost's (third-party, an <img> on the
//                   page); AcceptAll keeps both; BlockAll keeps neither
//   doNotTrack      requests carry "DNT: 1" while it is set
//   colorScheme     FollowsAmbience with Silica's default LightOnDark
//                   ambience: the page's prefers-color-scheme is dark
// and the WebView API Keel builds on Qt WebEngine's: frame scripts and the
// message manager through the isolated-world bridge, WebEngine's user
// style sheets, selection reported by the bridge, and `security` from a
// local TLS server with a self-signed certificate (made with openssl at
// run time; skipped without it).
// Built only where Qt WebEngine is.

#include <QGuiApplication>
#include <QFile>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QProcess>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslServer>
#include <QSslSocket>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QUrlQuery>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include <memory>

namespace {

struct Request
{
    QByteArray host;
    QByteArray path;
    QByteArray cookie;
    QByteArray dnt;
};

// A one-request-per-connection HTTP/1.0 server. /page?n=X sets the cookie
// first_X and shows localhost's /pixel?n=X, which sets third_X (SameSite=None
// and Secure, which Chromium accepts from http://localhost: without them its
// SameSite=Lax default would drop the cross-site cookie whatever the
// policy).
class HttpServer : public QTcpServer
{
public:
    QList<Request> requests;

    explicit HttpServer(QObject *parent = nullptr)
        : QTcpServer(parent)
    {
        connect(this, &QTcpServer::newConnection, this, [this] {
            while (QTcpSocket *socket = nextPendingConnection()) {
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket] { serve(socket); });
            }
        });
    }

private:
    QHash<QTcpSocket *, QByteArray> m_buffers;

    void serve(QTcpSocket *socket)
    {
        QByteArray &buffer = m_buffers[socket];
        buffer += socket->readAll();
        const qsizetype end = buffer.indexOf("\r\n\r\n");
        if (end < 0)
            return;
        const QList<QByteArray> lines = buffer.left(end).split('\n');
        m_buffers.remove(socket);
        Request request;
        const QList<QByteArray> requestLine = lines.value(0).trimmed().split(' ');
        request.path = requestLine.value(1);
        for (const QByteArray &line : lines.mid(1)) {
            const qsizetype colon = line.indexOf(':');
            const QByteArray name = line.left(colon).trimmed().toLower();
            const QByteArray value = line.mid(colon + 1).trimmed();
            if (name == "host")
                request.host = value.left(value.indexOf(':'));
            else if (name == "cookie")
                request.cookie = value;
            else if (name == "dnt")
                request.dnt = value;
        }
        requests.append(request);

        const QUrl url(QString::fromLatin1(request.path));
        const QByteArray n = QUrlQuery(url).queryItemValue(QStringLiteral("n")).toLatin1();
        QByteArray body;
        QByteArray headers;
        if (url.path() == QLatin1String("/page")) {
            body = "<html><head><title>-</title></head><body>"
                   "<img src=\"http://localhost:" + QByteArray::number(serverPort()) + "/pixel?n=" + n + "\">"
                   "<script>window.onload = function() { document.title = (matchMedia('(prefers-color-scheme: dark)')"
                   ".matches ? 'dark' : 'light') + '-' + innerWidth + '-" + n + "' }</script></body></html>";
            headers = "Content-Type: text/html\r\nSet-Cookie: first_" + n + "=1; Path=/\r\n";
        } else if (url.path() == QLatin1String("/dialogs")) {
            // A confirm() then a prompt(); the page title reports the answers.
            body = "<html><head><title>-</title></head><body><script>"
                   "window.onload = function() { var c = confirm('Continue?');"
                   " var p = prompt('Your name?', 'Ada');"
                   " document.title = 'answers:' + c + ':' + p }</script></body></html>";
            headers = "Content-Type: text/html\r\n";
        } else if (url.path() == QLatin1String("/bridge")) {
            body = "<html><head><title>bridge</title></head><body><p id=\"p\">Some text to select</p></body></html>";
            headers = "Content-Type: text/html\r\n";
        } else if (url.path() == QLatin1String("/qt")) {
            body = "<html><head><title>webkit</title></head><body><script>"
                   "navigator.qt.onmessage = function(m) { navigator.qt.postMessage('echo ' + m.data) };"
                   "window.onload = function() { navigator.qt.postMessage('hello ' + document.title) }"
                   "</script></body></html>";
            headers = "Content-Type: text/html\r\n";
        } else if (url.path() == QLatin1String("/pixel")) {
            body = "GIF89a";
            headers = "Content-Type: image/gif\r\nSet-Cookie: third_" + n + "=1; Path=/; SameSite=None; Secure\r\n";
        } else {
            socket->write("HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            socket->disconnectFromHost();
            return;
        }
        socket->write("HTTP/1.0 200 OK\r\nCache-Control: no-store\r\n" + headers + "Content-Length: "
                      + QByteArray::number(body.size()) + "\r\n\r\n" + body);
        socket->disconnectFromHost();
    }
};

const char *const Qml = R"(
import QtQuick 2.6
import QtQuick.Window 2.2
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0

Window {
    width: 320
    height: 320
    visible: true
    property alias loader: loader
    readonly property var view: loader.item
    readonly property real zoom: view && view._backend && view._backend.view ? view._backend.view.zoomFactor : 0

    function setPixelRatio(ratio) {
        WebEngineSettings.pixelRatio = ratio
    }

    function configure(cookieBehavior, doNotTrack) {
        WebEngineSettings.cookieBehavior = cookieBehavior
        WebEngineSettings.doNotTrack = doNotTrack
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: false
        // The app's shared, persistent profile (under the test's HOME).
        sourceComponent: WebView { }
    }
}
)";

} // namespace

class TestWebViewQtWebEngine : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void colorScheme();
    void pixelRatio();
    void blockThirdParty();
    void acceptAll();
    void blockAll();
    void javaScriptDialogs();
    void frameScriptsAndStyleSheets();
    void security();
    void silicaWebView();
    void cleanupTestCase();

private:
    // Loads /page?n=X twice; returns the requests of the second load.
    QList<Request> loadTwice(const QByteArray &n);
    QObject *view() const { return m_root->property("view").value<QObject *>(); }

    QTemporaryDir m_home;
    HttpServer m_server;
    std::unique_ptr<QQmlApplicationEngine> m_engine;
    QPointer<QObject> m_root;
};

void TestWebViewQtWebEngine::initTestCase()
{
    QVERIFY(m_home.isValid());
    qputenv("HOME", m_home.path().toLocal8Bit());
    qputenv("XDG_DATA_HOME", m_home.filePath(QStringLiteral("data")).toLocal8Bit());
    qputenv("XDG_CACHE_HOME", m_home.filePath(QStringLiteral("cache")).toLocal8Bit());
    qputenv("XDG_CONFIG_HOME", m_home.filePath(QStringLiteral("config")).toLocal8Bit());
    QVERIFY(m_server.listen(QHostAddress::LocalHost));

    m_engine = std::make_unique<QQmlApplicationEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
    m_engine->loadData(Qml);
    QCOMPARE(m_engine->rootObjects().size(), 1);
    m_root = m_engine->rootObjects().constFirst();
    QVERIFY(QMetaObject::invokeMethod(m_root, "configure", Q_ARG(QVariant, 1), Q_ARG(QVariant, true)));
    m_root->property("loader").value<QObject *>()->setProperty("active", true);
    QTRY_VERIFY(view());
    QTRY_COMPARE(view()->property("_engine").toString(), QStringLiteral("qtwebengine"));
}

QList<Request> TestWebViewQtWebEngine::loadTwice(const QByteArray &n)
{
    const QString page = QStringLiteral("http://127.0.0.1:%1/page?n=%2").arg(m_server.serverPort()).arg(QLatin1String(n));
    const QString title = QLatin1String("-") + QLatin1String(n);
    for (int round = 0; round < 2; ++round) {
        m_server.requests.clear();
        view()->setProperty("url", round == 0 ? page : page + QLatin1String("&again"));
        // The page and its image were both fetched, and the page finished.
        [&] {
            QTRY_VERIFY_WITH_TIMEOUT(m_server.requests.size() >= 2, 30000);
            QTRY_VERIFY_WITH_TIMEOUT(view()->property("title").toString().endsWith(title), 30000);
        }();
        if (QTest::currentTestFailed())
            return {};
    }
    return m_server.requests;
}

static const Request *find(const QList<Request> &requests, const QByteArray &host, const char *path)
{
    for (const Request &request : requests) {
        if (request.host == host && request.path.startsWith(path))
            return &request;
    }
    return nullptr;
}

void TestWebViewQtWebEngine::colorScheme()
{
    // FollowsAmbience (the default) under Silica's default LightOnDark
    // ambience asks Chromium for a dark scheme; its own default is light.
    const QList<Request> requests = loadTwice("s");
    QVERIFY(!requests.isEmpty());
    QVERIFY2(view()->property("title").toString().startsWith(QLatin1String("dark-")),
             qPrintable(view()->property("title").toString()));
}

// The page's width in CSS pixels: the view's 320 device pixels over
// pixelRatio, the default (1.5 times Theme.pixelRatio) and one set.
static int cssWidth(const QObject *view)
{
    return view->property("title").toString().section(QLatin1Char('-'), 1, 1).toInt();
}

void TestWebViewQtWebEngine::pixelRatio()
{
    QVERIFY(!loadTwice("p").isEmpty());
    const qreal defaultRatio = m_root->property("zoom").toReal();
    QVERIFY(defaultRatio >= 1.5);
    QVERIFY2(qAbs(cssWidth(view()) - qRound(320 / defaultRatio)) <= 1,
             qPrintable(view()->property("title").toString()));
    QVERIFY(QMetaObject::invokeMethod(m_root, "setPixelRatio", Q_ARG(QVariant, 2.0)));
    QVERIFY(!loadTwice("q").isEmpty());
    QCOMPARE(cssWidth(view()), 160);
}

void TestWebViewQtWebEngine::blockThirdParty()
{
    const QList<Request> requests = loadTwice("a");
    const Request *page = find(requests, "127.0.0.1", "/page");
    const Request *pixel = find(requests, "localhost", "/pixel");
    QVERIFY(page && pixel);
    QVERIFY2(page->cookie.contains("first_a=1"), page->cookie.constData());
    QVERIFY2(!pixel->cookie.contains("third_a"), pixel->cookie.constData());
    QCOMPARE(page->dnt, QByteArray("1"));
    QCOMPARE(pixel->dnt, QByteArray("1"));
}

void TestWebViewQtWebEngine::acceptAll()
{
    QVERIFY(QMetaObject::invokeMethod(m_root, "configure", Q_ARG(QVariant, 0), Q_ARG(QVariant, false)));
    const QList<Request> requests = loadTwice("b");
    const Request *page = find(requests, "127.0.0.1", "/page");
    const Request *pixel = find(requests, "localhost", "/pixel");
    QVERIFY(page && pixel);
    QVERIFY2(page->cookie.contains("first_b=1"), page->cookie.constData());
    QVERIFY2(pixel->cookie.contains("third_b=1"), pixel->cookie.constData());
    QVERIFY(page->dnt.isEmpty());
    QVERIFY(pixel->dnt.isEmpty());
}

void TestWebViewQtWebEngine::blockAll()
{
    QVERIFY(QMetaObject::invokeMethod(m_root, "configure", Q_ARG(QVariant, 2), Q_ARG(QVariant, false)));
    const QList<Request> requests = loadTwice("c");
    const Request *page = find(requests, "127.0.0.1", "/page");
    const Request *pixel = find(requests, "localhost", "/pixel");
    QVERIFY(page && pixel);
    QVERIFY2(!page->cookie.contains("first_c"), page->cookie.constData());
    QVERIFY2(!pixel->cookie.contains("third_c"), pixel->cookie.constData());
}

const char *const DialogsQml = R"(
import QtQuick 2.6
import QtQuick.Window 2.2
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

Window {
    id: root
    width: 540
    height: 960
    visible: true
    property alias stack: app.pageStack
    property Item view

    ApplicationWindow {
        id: app
        anchors.fill: parent
        initialPage: Component {
            WebViewPage {
                WebView {
                    id: view
                    anchors.fill: parent
                    Component.onCompleted: root.view = view
                }
            }
        }
    }
}
)";

void TestWebViewQtWebEngine::javaScriptDialogs()
{
    // The page's confirm() and prompt() open Sailfish's dialogs (through
    // Keel's message bridge); accepting them answers the page.
    QQmlComponent component(m_engine.get());
    component.setData(DialogsQml, QUrl(QStringLiteral("dialogs.qml")));
    std::unique_ptr<QObject> window(component.create());
    QVERIFY2(window, qPrintable(component.errorString()));
    QTRY_VERIFY(window->property("view").value<QObject *>());
    auto *view = window->property("view").value<QObject *>();
    QTRY_COMPARE(view->property("_engine").toString(), QStringLiteral("qtwebengine"));
    auto *stack = window->property("stack").value<QObject *>();
    auto *webPage = stack->property("currentPage").value<QObject *>();
    view->setProperty("url", QStringLiteral("http://127.0.0.1:%1/dialogs").arg(m_server.serverPort()));

    auto answer = [&](const char *what, const QVariant &value) {
        QTRY_VERIFY_WITH_TIMEOUT(stack->property("currentPage").value<QObject *>() != webPage
                                     && !stack->property("busy").toBool(),
                                 30000);
        auto *dialog = stack->property("currentPage").value<QObject *>();
        QVERIFY2(dialog->property("text").toString().contains(QLatin1String(what)),
                 qPrintable(dialog->property("text").toString()));
        if (value.isValid())
            dialog->setProperty("value", value);
        QVERIFY(QMetaObject::invokeMethod(dialog, "accept"));
        QTRY_COMPARE(stack->property("currentPage").value<QObject *>(), webPage);
    };
    answer("Continue?", {});
    answer("Your name?", QStringLiteral("Grace"));
    QTRY_COMPARE_WITH_TIMEOUT(view->property("title").toString(), QStringLiteral("answers:true:Grace"), 30000);
}

const char *const BridgeQml = R"(
import QtQuick 2.6
import QtQuick.Window 2.2
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0

Window {
    width: 320
    height: 320
    visible: true
    property alias view: view
    property var messages: []

    function addStyleSheet(url) { WebEngine.addUserStyleSheet(url) }

    WebView {
        id: view
        anchors.fill: parent
        onRecvAsyncMessage: function(message, data) { messages = messages.concat([[message, data]]) }
    }
}
)";

void TestWebViewQtWebEngine::frameScriptsAndStyleSheets()
{
    // A frame script answers the app's message with what it sees in the
    // page, including the colour WebEngine's user style sheet gave it.
    const QString script = m_home.filePath(QStringLiteral("frame.js"));
    QFile scriptFile(script);
    QVERIFY(scriptFile.open(QIODevice::WriteOnly));
    scriptFile.write("addMessageListener('test:ping', function(message) {\n"
                     "  sendAsyncMessage('test:pong', { title: content.document.title, echo: message.data.n,\n"
                     "    color: content.getComputedStyle(content.document.body).color });\n"
                     "});\n"
                     "addEventListener('DOMContentLoaded', function() { sendAsyncMessage('test:loaded', {}); });\n");
    scriptFile.close();
    const QString css = m_home.filePath(QStringLiteral("user.css"));
    QFile cssFile(css);
    QVERIFY(cssFile.open(QIODevice::WriteOnly));
    cssFile.write("body { color: rgb(1, 2, 3); }\n");
    cssFile.close();

    QQmlComponent component(m_engine.get());
    component.setData(BridgeQml, QUrl(QStringLiteral("bridge.qml")));
    std::unique_ptr<QObject> window(component.create());
    QVERIFY2(window, qPrintable(component.errorString()));
    auto *view = window->property("view").value<QObject *>();
    QTRY_COMPARE(view->property("_engine").toString(), QStringLiteral("qtwebengine"));
    QVERIFY(QMetaObject::invokeMethod(window.get(), "addStyleSheet", Q_ARG(QVariant, QUrl::fromLocalFile(css))));
    QVERIFY(QMetaObject::invokeMethod(view, "addMessageListener", Q_ARG(QVariant, QStringLiteral("test:pong"))));
    QVERIFY(QMetaObject::invokeMethod(view, "addMessageListener", Q_ARG(QVariant, QStringLiteral("test:loaded"))));
    QVERIFY(QMetaObject::invokeMethod(view, "loadFrameScript", Q_ARG(QVariant, QUrl::fromLocalFile(script))));
    view->setProperty("url", QStringLiteral("http://127.0.0.1:%1/bridge").arg(m_server.serverPort()));
    QTRY_VERIFY_WITH_TIMEOUT(view->property("loaded").toBool(), 30000);

    auto received = [&](const QString &name) -> QVariantMap {
        const QVariantList messages = window->property("messages").toList();
        for (const QVariant &m : messages) {
            const QVariantList pair = m.toList();
            if (pair.value(0).toString() == name)
                return pair.value(1).toMap();
        }
        return {};
    };
    auto has = [&](const QString &name) {
        const QVariantList messages = window->property("messages").toList();
        for (const QVariant &m : messages) {
            if (m.toList().value(0).toString() == name)
                return true;
        }
        return false;
    };
    // The frame script ran at the document's creation.
    QTRY_VERIFY_WITH_TIMEOUT(has(QStringLiteral("test:loaded")), 30000);
    const QVariant ping = QVariantMap { { QStringLiteral("n"), 7 } };
    QVERIFY(QMetaObject::invokeMethod(view, "sendAsyncMessage", Q_ARG(QVariant, QStringLiteral("test:ping")),
                                      Q_ARG(QVariant, ping)));
    QTRY_VERIFY_WITH_TIMEOUT(has(QStringLiteral("test:pong")), 30000);
    const QVariantMap pong = received(QStringLiteral("test:pong"));
    QCOMPARE(pong.value(QStringLiteral("title")).toString(), QStringLiteral("bridge"));
    QCOMPARE(pong.value(QStringLiteral("echo")).toInt(), 7);
    QCOMPARE(pong.value(QStringLiteral("color")).toString(), QStringLiteral("rgb(1, 2, 3)"));

    // Selecting text in the page is reported.
    QVERIFY(!view->property("textSelectionActive").toBool());
    QVERIFY(QMetaObject::invokeMethod(view, "runJavaScript",
                                      Q_ARG(QVariant, QStringLiteral("var r = document.createRange();"
                                                                     " r.selectNodeContents(document.getElementById('p'));"
                                                                     " getSelection().addRange(r); return true")),
                                      Q_ARG(QVariant, QVariant()), Q_ARG(QVariant, QVariant())));
    QTRY_VERIFY_WITH_TIMEOUT(view->property("textSelectionActive").toBool(), 30000);
    QVERIFY(QMetaObject::invokeMethod(view, "clearSelection"));
    QTRY_VERIFY_WITH_TIMEOUT(!view->property("textSelectionActive").toBool(), 30000);
}

namespace {

// A TLS server that completes handshakes with a self-signed certificate
// for "keel.test" and closes the connection.
class TlsServer : public QSslServer
{
public:
    explicit TlsServer(const QSslCertificate &certificate, const QSslKey &key)
    {
        QSslConfiguration configuration = QSslConfiguration::defaultConfiguration();
        configuration.setLocalCertificate(certificate);
        configuration.setPrivateKey(key);
        configuration.setPeerVerifyMode(QSslSocket::VerifyNone);
        setSslConfiguration(configuration);
        connect(this, &QSslServer::pendingConnectionAvailable, this, [this] {
            while (QTcpSocket *socket = nextPendingConnection()) {
                connect(socket, &QTcpSocket::readyRead, socket, [socket] {
                    socket->write("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: 4\r\n\r\nsafe");
                    socket->disconnectFromHost();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }
};

} // namespace

void TestWebViewQtWebEngine::security()
{
    if (!QSslSocket::supportsSsl())
        QSKIP("no TLS backend");
    const QString keyPath = m_home.filePath(QStringLiteral("tls.key"));
    const QString certPath = m_home.filePath(QStringLiteral("tls.crt"));
    QProcess openssl;
    openssl.start(QStringLiteral("openssl"),
                  { QStringLiteral("req"), QStringLiteral("-x509"), QStringLiteral("-newkey"), QStringLiteral("rsa:2048"),
                    QStringLiteral("-nodes"), QStringLiteral("-days"), QStringLiteral("2"), QStringLiteral("-subj"),
                    QStringLiteral("/CN=keel.test/O=Shipwright Test"), QStringLiteral("-keyout"), keyPath,
                    QStringLiteral("-out"), certPath });
    if (!openssl.waitForStarted() || !openssl.waitForFinished(60000) || openssl.exitCode() != 0)
        QSKIP("openssl is needed to make the test certificate");
    QFile certFile(certPath);
    QFile keyFile(keyPath);
    QVERIFY(certFile.open(QIODevice::ReadOnly) && keyFile.open(QIODevice::ReadOnly));
    TlsServer server(QSslCertificate(&certFile), QSslKey(&keyFile, QSsl::Rsa));
    QVERIFY(server.listen(QHostAddress::LocalHost));

    QQmlComponent component(m_engine.get());
    component.setData(BridgeQml, QUrl(QStringLiteral("security.qml")));
    std::unique_ptr<QObject> window(component.create());
    QVERIFY2(window, qPrintable(component.errorString()));
    auto *view = window->property("view").value<QObject *>();
    QTRY_COMPARE(view->property("_engine").toString(), QStringLiteral("qtwebengine"));
    auto *security = view->property("security").value<QObject *>();
    QVERIFY(security);

    // Plain http: insecure.
    view->setProperty("url", QStringLiteral("http://127.0.0.1:%1/bridge").arg(m_server.serverPort()));
    QTRY_VERIFY_WITH_TIMEOUT(view->property("loaded").toBool(), 30000);
    QVERIFY(security->property("validState").toBool());
    QVERIFY(security->property("isInsecure").toBool());
    QVERIFY(!security->property("allGood").toBool());

    // A self-signed certificate: Chromium refuses the page; the state is
    // broken and untrusted, with the server's certificate.
    view->setProperty("url", QStringLiteral("https://127.0.0.1:%1/").arg(server.serverPort()));
    QTRY_VERIFY_WITH_TIMEOUT(security->property("isBroken").toBool(), 30000);
    QVERIFY(security->property("untrusted").toBool());
    QVERIFY(!security->property("allGood").toBool());
    QTRY_COMPARE_WITH_TIMEOUT(security->property("subjectDisplayName").toString(), QStringLiteral("keel.test"), 30000);
    QCOMPARE(security->property("subjectOrganization").toString(), QStringLiteral("Shipwright Test"));
    QCOMPARE(security->property("issuerDisplayName").toString(), QStringLiteral("keel.test"));
    QVERIFY(!security->property("certIsNull").toBool());
    QVERIFY(security->property("protocolVersion").toInt() >= 3); // TLS 1.2 or 1.3
    QVERIFY(!security->property("cipherName").toString().isEmpty());
    const QVariantMap details = security->property("serverCertDetails").toMap();
    QCOMPARE(details.value(QStringLiteral("SubjectDisplayName")).toString(), QStringLiteral("keel.test"));
    QCOMPARE(details.value(QStringLiteral("Subject")).toMap().value(QStringLiteral("CN")).toString(),
             QStringLiteral("keel.test"));
    QVERIFY(details.value(QStringLiteral("Validity")).toMap().value(QStringLiteral("NotAfter")).toDateTime().isValid());
}

const char *const SilicaQml = R"(
import QtQuick 2.6
import QtQuick.Window 2.2
import Sailfish.Silica 1.0

Window {
    width: 320
    height: 480
    visible: true
    property alias view: view
    property var messages: []

    SilicaWebView {
        id: view
        anchors.fill: parent
        experimental.onMessageReceived: function(message) { messages = messages.concat([message.data]) }
    }
}
)";

void TestWebViewQtWebEngine::silicaWebView()
{
    // Silica's SilicaWebView on Keel's WebView: QtWebKit's navigator.qt
    // carries messages both ways.
    QQmlComponent component(m_engine.get());
    component.setData(SilicaQml, QUrl(QStringLiteral("silica.qml")));
    std::unique_ptr<QObject> window(component.create());
    QVERIFY2(window, qPrintable(component.errorString()));
    auto *view = window->property("view").value<QObject *>();
    view->setProperty("url", QStringLiteral("http://127.0.0.1:%1/qt").arg(m_server.serverPort()));
    QTRY_COMPARE_WITH_TIMEOUT(view->property("title").toString(), QStringLiteral("webkit"), 30000);
    QTRY_VERIFY_WITH_TIMEOUT(window->property("messages").toList().contains(QStringLiteral("hello webkit")), 30000);
    auto *experimental = view->property("experimental").value<QObject *>();
    QVERIFY(QMetaObject::invokeMethod(experimental, "postMessage", Q_ARG(QVariant, QStringLiteral("ping"))));
    QTRY_VERIFY_WITH_TIMEOUT(window->property("messages").toList().contains(QStringLiteral("echo ping")), 30000);
    QCOMPARE(view->property("loadRequest").toMap().value(QStringLiteral("status")).toInt(), 2); // LoadSucceededStatus
}

void TestWebViewQtWebEngine::cleanupTestCase()
{
    m_engine.reset();
}

int main(int argc, char *argv[])
{
    // Chromium in a container: no sandbox, no GPU.
    qputenv("QTWEBENGINE_DISABLE_SANDBOX", "1");
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", "--no-sandbox --disable-gpu");
    // The WebView's own TLS connection is what security() tests.
    qunsetenv("KEEL_WEBVIEW_CERTIFICATES");
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    TestWebViewQtWebEngine test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_webview_qtwebengine.moc"
