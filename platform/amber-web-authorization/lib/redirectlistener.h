// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#ifndef AMBER_WEB_AUTHORIZATION_REDIRECTLISTENER_H
#define AMBER_WEB_AUTHORIZATION_REDIRECTLISTENER_H

#include "oauthsymbols.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Amber {

namespace Web {

namespace Authorization {

class RedirectListenerPrivate;
class EXPORT_SYMBOL RedirectListener : public QObject
{
    Q_OBJECT
    Q_DECLARE_PRIVATE(RedirectListener)

    Q_PROPERTY(int timeout READ timeout WRITE setTimeout NOTIFY timeoutChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString uri READ uri NOTIFY uriChanged)
    Q_PROPERTY(QString httpContent READ httpContent WRITE setHttpContent NOTIFY httpContentChanged)

public:
    RedirectListener(QObject *parent = nullptr);
    ~RedirectListener();

    Q_INVOKABLE void startListening();
    Q_INVOKABLE void stopListening();

    int timeout() const;
    void setTimeout(int timeout);

    int port() const;
    void setPort(int p);
    QString uri() const;

    QString httpContent() const;
    void setHttpContent(const QString &httpContent);

Q_SIGNALS:
    void timeoutChanged();
    void portChanged();
    void uriChanged();
    void httpContentChanged();
    void receivedRedirect(const QString &redirectUri);
    void timedOut();
    void failed();

private:
    QScopedPointer<RedirectListenerPrivate> const d_ptr;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

#endif // AMBER_WEB_AUTHORIZATION_REDIRECTLISTENER_H
