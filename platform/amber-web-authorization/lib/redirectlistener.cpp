// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#include "redirectlistener.h"

#include <QtCore/QTimer>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>

namespace Amber {

namespace Web {

namespace Authorization {

class RedirectListenerPrivate
{
    Q_DISABLE_COPY(RedirectListenerPrivate)

public:
    explicit RedirectListenerPrivate() {}

    QTcpServer *m_tcpServer = nullptr;
    QTimer *m_timeoutTimer = nullptr;
    int m_timeout = 300; // default: 60 * 5 = 300 seconds.
    int m_port = 0;
    QString m_uri;
    QString m_httpContent = QStringLiteral(
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/html\r\n"
            "Connection: close\r\n\r\n"
            "<!DOCTYPE html>\r\n"
            "<html></html>\r\n\r\n");
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

/*!
  \class Amber::Web::Authorization::RedirectListener
  \brief Provides a helper to allow applications to listen for localhost OAuth redirects.
  \inmodule AmberWebAuthorization

  Most OAuth flows require user interaction, which is initiated by the client
  application by opening an authorization URL in the system web browser.
  Once the user authorizes the application, the web browser will be redirected
  to the redirect URI specified by the client application.

  Most services support either "localhost" or "custom protocol" redirects.
  This helper is a simple TCP server which listens on a specified port on the
  localhost address, allowing the application to receive the redirect from the
  system web browser (which will contain important information from the server
  which is required to complete the OAuth flow).

  Note: the client application will need to specify that it uses a localhost
  redirect URI in the server-side application configuration (e.g. developer
  console or similar) in order to successfully make use of this helper.

  Also note that the QML API contains flow-specific helpers
  (e.g. \c{OAuth2AcPkce}) which include both the \l{OAuth2} helper and the
  \l{RedirectListener} helper, with the appropriate property bindings set up
  already, and so this class is mostly of interest to C++ clients or clients
  who have unusual redirect handling requirements.

  \sa amberwebauthcppexample
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::RedirectListener::receivedRedirect(const QString &redirectUri)
  \brief This signal is emitted when the helper receives a redirect from the system web browser.

  The \a redirectUri will contain the full URI, including fragment and query
  parameters.  This can then be parsed (e.g. using the \c{parseRedirectUri()}
  method provided by either \l{OAuth1} or \c{OAuth2} helper types) to extract
  the meaningful information (bearer code, access token, error message, etc).
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::RedirectListener::failed()
  \brief This signal is emitted if the helper cannot listen for redirects.

  If the port is specified by the client but is unavailable, or if no port
  was specified and no available port could be found, the helper will be
  unable to listen for redirects.
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::RedirectListener::timedOut()
  \brief This signal is emitted if the helper does not receive a redirect
         within the specified timeout interval.

  \sa timeout
*/

/*!
  \brief Constructs a new RedirectListener helper instance, with the specified QObject \a parent.
*/
Amber::Web::Authorization::RedirectListener::RedirectListener(QObject *parent)
    : QObject(parent)
    , d_ptr(new RedirectListenerPrivate)
{
}

/*!
  \brief Destroys the RedirectListener helper instance
*/
Amber::Web::Authorization::RedirectListener::~RedirectListener()
{
}

/*!
  \property Amber::Web::Authorization::RedirectListener::timeout
  \brief This property holds the amount of time (in seconds)
         that the listener should wait for redirects for, before
         it will emit the \l{timedOut()} signal.

  The timeout timer will be started once \l{startListening()} is invoked,
  and stopped if \l{stopListening()} is invoked or if the redirect
  is received prior to the timeout interval being exceeded.

  The value should be high enough to give the user plenty of time to inspect
  the access being requested by the application and complete the authorization
  flow in the web browser.

  If the timeout is reached, this is usually indicative of an error (for
  example, the web browser application did not launch successfully).

  The default value is 300 (seconds, i.e. five minutes).

  A zero or negative value will result in no timeout timer being
  started.
*/
int Amber::Web::Authorization::RedirectListener::timeout() const
{
    Q_D(const RedirectListener);
    return d->m_timeout;
}

void Amber::Web::Authorization::RedirectListener::setTimeout(int timeout)
{
    Q_D(RedirectListener);
    if (d->m_timeout != timeout) {
        d->m_timeout = timeout;
        emit timeoutChanged();
    }
}

/*!
  \property Amber::Web::Authorization::RedirectListener::port
  \brief This property holds the port that the client application wishes the
         helper to listen on for redirects.

  If no value is specified by the client (or if an invalid value is specified)
  the helper will attempt to listen on an arbitrary valid port above 1024.

  The default value is 0 (i.e. the helper will listen on an arbitrary port).
*/
int Amber::Web::Authorization::RedirectListener::port() const
{
    Q_D(const RedirectListener);
    return d->m_port;
}

void Amber::Web::Authorization::RedirectListener::setPort(int p)
{
    Q_D(RedirectListener);
    if (d->m_port != p) {
        d->m_port = p;
        emit portChanged();
    }
}

/*!
  \property Amber::Web::Authorization::RedirectListener::uri
  \brief This property holds the full URI of the listener.

  It will be of the form \c{"http://127.0.0.1:<port>/"} where the \c{<port>}
  value will either be the \l{port} property value (if the client provided
  a valid port number via this property) or else an arbitrary valid port,
  which the helper was able to listen on.

  The full URI will only be known after the helper successfully begins to
  listen, and so this value will change after the client invokes the
  \l{startListening()} method.  Thus, the client application should connect
  to the \l{uriChanged()} signal in order to react to changes, in order to
  set this \c{uri} value as the \c{redirectUri} property of the
  \l{OAuth1} or \l{OAuth2} helper being used (or in QML, bind them
  appropriately).

  \sa startListening()
*/
QString Amber::Web::Authorization::RedirectListener::uri() const
{
    Q_D(const RedirectListener);
    return d->m_uri;
}

/*!
  \property Amber::Web::Authorization::RedirectListener::httpContent
  \brief This property holds the HTTP content which will be sent to the web browser.

  When the helper receives a redirect from the system web browser, it captures
  the redirect information and then sends back some HTTP content (which will
  be displayed to the user in the web browser).

  The client application should provide HTTP content which is user-friendly
  and appropriately translated, informing the user that they can close the
  web browser window and return to using the client application.

  The default value will simply display a blank webpage:
  \code
  "HTTP/1.1 200 OK\\r\\n"
  "Content-Type: text/html\\r\\n"
  "Connection: close\\r\\n\\r\\n"
  "<!DOCTYPE html>\\r\\n"
  "<html></html>\\r\\n\\r\\n"
  \endcode
*/
QString Amber::Web::Authorization::RedirectListener::httpContent() const
{
    Q_D(const RedirectListener);
    return d->m_httpContent;
}

void Amber::Web::Authorization::RedirectListener::setHttpContent(const QString &httpContent)
{
    Q_D(RedirectListener);
    if (d->m_httpContent != httpContent) {
        d->m_httpContent = httpContent;
    }
}

/*!
  \brief Stop listening for redirects from the system web browser.

  This method will be called automatically if the \l{timeout} interval is
  reached when listening for directs, or once a valid redirect is captured.

  Clients may call this manually in order to stop listening.
*/
void Amber::Web::Authorization::RedirectListener::stopListening()
{
    Q_D(RedirectListener);
    if (d->m_tcpServer) {
        d->m_tcpServer->close();
        d->m_tcpServer->deleteLater(); // will delete m_timeoutTimer (child).
        d->m_tcpServer = nullptr;
        d->m_timeoutTimer = nullptr;
    }
}

/*!
  \brief Start listening for redirects from the system web browser.

  The client application should call this method in order to make the helper
  start to listen for redirects.  If a \l{port} has been specified by the
  client application, the helper will attempt to listen on that port;
  otherwise, the helper will attempt to listen on an arbitrary port above 1024.

  If the helper is unable to listen (e.g. due to the specified \l{port} being
  unavailable, or due to no ports being available to the application if the
  \l{port} is left as the default 0 value), it will \l{stopListening()} and
  emit the \l{failed()} signal.

  Otherwise, the helper will listen for up to \l{timeout} seconds before
  emitting the \l{timedOut()} signal and \l{stopListening()}.

  If a redirect is received, it will write the \l{httpContent} to the socket,
  and then \l{stopListening()} before emitting \l{receivedRedirect()}.
*/
void Amber::Web::Authorization::RedirectListener::startListening()
{
    Q_D(RedirectListener);
    if (d->m_tcpServer) {
        // already listening
        return;
    }

    d->m_tcpServer = new QTcpServer(this);
    d->m_timeoutTimer = new QTimer(d->m_tcpServer);
    d->m_timeoutTimer->setInterval(d->m_timeout * 1000);
    d->m_timeoutTimer->setSingleShot(true);
    if (d->m_timeout > 0) {
        d->m_timeoutTimer->start();
    }
    connect(d->m_timeoutTimer, &QTimer::timeout,
            d->m_timeoutTimer, [this] {
        stopListening();
        emit timedOut();
    });

    bool found = false;
    if (d->m_port > 0 && d->m_port < 65534) {
        // use the port specified by the client
        const quint16 p = d->m_port;
        if (d->m_tcpServer->listen(QHostAddress(QHostAddress::LocalHost), p)) {
            d->m_uri = QStringLiteral("http://127.0.0.1:%1/").arg(p);
            emit uriChanged();
            found = true;
        }
    } else {
        // search for an available port
        for (quint16 p = 1025; p < 65534; ++p) {
            if (d->m_tcpServer->listen(QHostAddress(QHostAddress::LocalHost), p)) {
                d->m_uri = QStringLiteral("http://127.0.0.1:%1/").arg(p);
                emit uriChanged();
                found = true;
                break;
            }
        }
    }

    if (!found) {
        // unable to listen, no available ports.
        stopListening();
        emit failed();
        return;
    }

    connect(d->m_tcpServer, &QTcpServer::newConnection,
            d->m_tcpServer, [this] {
        QTcpSocket *socket = d_ptr->m_tcpServer->nextPendingConnection();
        connect(socket, &QTcpSocket::disconnected,
                this, [socket] {
            socket->deleteLater();
        });

        connect(socket, &QIODevice::readyRead,
                d_ptr->m_tcpServer, [this, socket] {
            const QByteArray data = socket->readAll();
            const int indexOfPath = data.indexOf('/') + 1;
            const int indexOfSpace = data.indexOf(' ', indexOfPath);
            const QByteArray redirectRequest = data.mid(indexOfPath, indexOfSpace - indexOfPath);
            const QString redirectUri = QStringLiteral("%1%2").arg(d_ptr->m_uri).arg(QString::fromUtf8(redirectRequest));

            socket->write(d_ptr->m_httpContent.toUtf8());
            socket->flush();
            socket->disconnectFromHost(); // we specify "Connection: close"

            stopListening();
            emit receivedRedirect(redirectUri);
        });
    });
}
