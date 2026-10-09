// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Amber.Web.Authorization (amber-web-authorization for Qt 6) as
// sfos-forum-viewer's login page uses it: OAuth1.parseRedirectUri() and a
// RedirectListener listening on a local port for the web page's redirect,
// which an HTTP request to that port delivers to onReceivedRedirect.

#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTcpSocket>
#include <QTest>
#include <QUrl>
#include <memory>

class tst_Amber : public QObject
{
    Q_OBJECT

private slots:
    void loginHelpers();
    void flowHelpers();
};

void tst_Amber::loginHelpers()
{
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    QQmlComponent c(&engine);
    c.setData(R"QML(
import QtQuick 2.0
import Amber.Web.Authorization 1.0
Item {
    property alias listener: listener
    property var parsed
    property string payload
    OAuth1 { id: parser }
    RedirectListener {
        id: listener
        onReceivedRedirect: payload = parser.parseRedirectUri(redirectUri)["payload"]
    }
    Component.onCompleted: {
        parsed = parser.parseRedirectUri("http://localhost/cb?oauth_token=abc&oauth_verifier=xyz")
        listener.startListening()
    }
})QML",
              QUrl(QStringLiteral("login.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    const QVariantMap parsed = o->property("parsed").toMap();
    QCOMPARE(parsed.value(QStringLiteral("oauth_token")).toString(), QStringLiteral("abc"));
    QCOMPARE(parsed.value(QStringLiteral("oauth_verifier")).toString(), QStringLiteral("xyz"));
    auto *listener = o->property("listener").value<QObject *>();
    // Listening on a local port: the redirect URI the login page hands out.
    QTRY_VERIFY(listener->property("uri").toString().startsWith(QLatin1String("http://")));
    const QUrl uri(listener->property("uri").toString());
    QVERIFY2(uri.port() > 0, qPrintable(uri.toString()));

    // The page redirects to the listener: a plain HTTP GET with the payload.
    QSignalSpy redirected(listener, SIGNAL(receivedRedirect(QString)));
    QTcpSocket http;
    http.connectToHost(QStringLiteral("127.0.0.1"), static_cast<quint16>(uri.port()));
    QVERIFY(http.waitForConnected(5000));
    http.write("GET /?payload=abc%2Fdef HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    QTRY_COMPARE(redirected.count(), 1);
    QCOMPARE(o->property("payload").toString(), QStringLiteral("abc%2Fdef"));
}

// The upstream QML helpers (OAuth10a, OAuth2Ac, OAuth2AcPkce,
// OAuth2Implicit) load on Qt 6, with their onErrorChanged handlers and the
// Error enums they use.
void tst_Amber::flowHelpers()
{
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    QQmlComponent c(&engine);
    c.setData(R"QML(
import QtQuick 2.0
import Amber.Web.Authorization 1.0
Item {
    property int networkError: Error.NetworkError
    property var helpers: [a, b, c, d]
    OAuth10a { id: a }
    OAuth2Ac { id: b }
    OAuth2AcPkce { id: c }
    OAuth2Implicit { id: d }
})QML",
              QUrl(QStringLiteral("flows.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QCOMPARE(o->property("helpers").toList().size(), 4);
    QVERIFY(o->property("networkError").toInt() > 0);
}

QTEST_MAIN(tst_Amber)
#include "tst_amber.moc"
