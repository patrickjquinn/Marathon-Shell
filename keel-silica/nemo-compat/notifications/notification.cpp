// SPDX-FileCopyrightText: 2013 - 2019 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2013 - 2019 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */
#include "notificationmanagerproxy.h"
#include "notification.h"
#include "notification_p.h"

#include <QImage>
#include <QStringBuilder>
#include <QDebug>

#include <time.h>

#define DBUS_SERVICE "org.freedesktop.Notifications"
#define DBUS_PATH "/org/freedesktop/Notifications"

namespace {

const char *HINT_CATEGORY = "category";
const char *HINT_URGENCY = "urgency";
const char *HINT_TRANSIENT = "transient";
const char *HINT_RESIDENT = "resident";
const char *HINT_ITEM_COUNT = "x-nemo-item-count";
const char *HINT_TIMESTAMP = "x-nemo-timestamp";
const char *HINT_PREVIEW_BODY = "x-nemo-preview-body";
const char *HINT_PREVIEW_SUMMARY = "x-nemo-preview-summary";
const char *HINT_SUB_TEXT = "x-nemo-sub-text";
const char *HINT_REMOTE_ACTION_PREFIX = "x-nemo-remote-action-";
const char *HINT_REMOTE_ACTION_ICON_PREFIX = "x-nemo-remote-action-icon-";
const char *HINT_REMOTE_ACTION_INPUT_PREFIX = "x-nemo-remote-action-input-";
const char *HINT_REMOTE_ACTION_TYPE_PREFIX = "x-nemo-remote-action-type-";
const char *HINT_ORIGIN = "x-nemo-origin";
const char *HINT_OWNER = "x-nemo-owner";
const char *HINT_MAX_CONTENT_LINES = "x-nemo-max-content-lines";
const char *DEFAULT_ACTION_NAME = "default";
const char *HINT_PROGRESS = "x-nemo-progress";
const char *HINT_SOUND_FILE = "sound-file";
const char *HINT_SOUND_NAME = "sound-name";
const char *HINT_IMAGE_DATA = "image-data";
const char *HINT_IMAGE_PATH = "image-path";

class NotificationImage : public QImage
{
public:
    NotificationImage() = default;
    NotificationImage(const QImage &image)
        : QImage(image.format() == QImage::Format_RGB32 || image.format() == QImage::Format_ARGB32
                 ? QImage(image)
                 : image.convertToFormat(image.hasAlphaChannel() ? QImage::Format_ARGB32 : QImage::Format_RGB32))
    {
    };
};

// Marshall the MyStructure data into a D-Bus argument
QDBusArgument &operator <<(QDBusArgument &argument, const NotificationImage &image)
{
    argument.beginStructure();
    argument << image.width();
    argument << image.height();
    argument << image.bytesPerLine();
    argument << image.hasAlphaChannel();
    argument << 8;
    argument << 4;
#if (QT_VERSION >= QT_VERSION_CHECK(5, 10, 0))
    argument << QByteArray(reinterpret_cast<const char *>(image.bits()), image.sizeInBytes());
#else
    argument << QByteArray(reinterpret_cast<const char *>(image.bits()), image.byteCount());
#endif
    argument.endStructure();

    return argument;
}

const QDBusArgument &operator >>(const QDBusArgument &argument, NotificationImage &)
{
    return argument;
}

}

Q_DECLARE_METATYPE(NotificationImage)

namespace {

static inline QString processName() {
    // Defaults to the filename if not set
    return QCoreApplication::applicationName();
}

Q_GLOBAL_STATIC(NotificationConnectionManager, connMgr)

NotificationManagerProxy *notificationManager()
{
    if (connMgr()->proxy.isNull()) {
        qDBusRegisterMetaType<NotificationData>();
        qDBusRegisterMetaType<QList<NotificationData> >();
        qDBusRegisterMetaType<NotificationImage>();
        QString serviceName(DBUS_SERVICE);
        QDBusConnection *conn = connMgr()->dBusConnection.data();
        if (conn && conn->isConnected() && conn->baseService().isEmpty()) {
            // p2p connection - no service name
            serviceName.clear();
        }
        connMgr()->proxy.reset(new NotificationManagerProxy(serviceName, DBUS_PATH, 
                        conn ? *conn : QDBusConnection::sessionBus()));
    }
    return connMgr()->proxy.data();
}

QString encodeDBusCall(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &arguments)
{
    const QString space(QStringLiteral(" "));

    QString s = service % space % path % space % iface % space % method;

    if (!arguments.isEmpty()) {
        QStringList args;
        int argsLength = 0;

        foreach (const QVariant &arg, arguments) {
            // Serialize the QVariant into a Base64 encoded byte stream
            QByteArray buffer;
            QDataStream stream(&buffer, QIODevice::WriteOnly);
            stream << arg;
            args.append(space + buffer.toBase64());
            argsLength += args.last().length();
        }

        s.reserve(s.length() + argsLength);
        foreach (const QString &arg, args) {
            s.append(arg);
        }
    }

    return s;
}

QStringList encodeActions(const QList<NotificationData::ActionInfo> &actions)
{
    QStringList rv;

    // Actions are encoded as a sequence of name followed by displayName
    for (const NotificationData::ActionInfo &actionInfo : actions) {
        rv.append(actionInfo.name);
        rv.append(actionInfo.displayName);
    }

    return rv;
}

QList<NotificationData::ActionInfo> decodeActions(const QStringList &actions)
{
    QList<NotificationData::ActionInfo> rv;

    QStringList::const_iterator it = actions.constBegin(), end = actions.constEnd();
    while (it != end) {
        NotificationData::ActionInfo actionInfo;
        actionInfo.name = *it;
        // If we have an odd number of tokens, add an empty displayName to complete the last pair
        if (++it != end) {
            actionInfo.displayName = *it;
            ++it;
        }
        rv.append(actionInfo);
    }

    return rv;
}

QPair<QList<NotificationData::ActionInfo>, QVariantHash> encodeActionHints(const QVariantList &actions)
{
    QPair<QList<NotificationData::ActionInfo>, QVariantHash> rv;
    foreach (const QVariant &action, actions) {
        QVariantMap vm = action.value<QVariantMap>();
        const QString actionName = vm["name"].value<QString>();
        if (!actionName.isEmpty()) {
            const QString displayName = vm["displayName"].value<QString>();
            const QString service = vm["service"].value<QString>();
            const QString path = vm["path"].value<QString>();
            const QString iface = vm["iface"].value<QString>();
            const QString method = vm["method"].value<QString>();
            const QVariantList arguments = vm["arguments"].value<QVariantList>();
            const QString icon = vm["icon"].value<QString>();
            const QVariantMap input = vm["input"].value<QVariantMap>();
            QString type = vm["type"].value<QString>();

            const NotificationData::ActionInfo actionInfo = { actionName, displayName };
            rv.first.append(actionInfo);

            if (!service.isEmpty() && !path.isEmpty() && !iface.isEmpty() && !method.isEmpty()) {
                rv.second.insert(QString(HINT_REMOTE_ACTION_PREFIX) + actionName, encodeDBusCall(service, path, iface, method, arguments));
            }
            if (!icon.isEmpty()) {
                rv.second.insert(QString(HINT_REMOTE_ACTION_ICON_PREFIX) + actionName, icon);
            }
            if (!input.isEmpty()) {
                rv.second.insert(QString(HINT_REMOTE_ACTION_INPUT_PREFIX) + actionName, input);
                if (type.isEmpty()) {
                    type = QLatin1String("input");
                }
            }
            if (!type.isEmpty()) {
                rv.second.insert(QString(HINT_REMOTE_ACTION_TYPE_PREFIX) + actionName, type);
            }
        }
    }

    return rv;
}

QVariantList decodeActionHints(const QList<NotificationData::ActionInfo> &actions, const QVariantHash &hints)
{
    QVariantList rv;

    for (const NotificationData::ActionInfo &actionInfo : actions) {
        const QString &actionName = actionInfo.name;
        const QString &displayName = actionInfo.displayName;

        const QString hintName = QString(HINT_REMOTE_ACTION_PREFIX) + actionName;
        const QString &hint = hints[hintName].toString();
        if (!hint.isEmpty()) {
            QVariantMap action;

            // Extract the element of the DBus call
#if (QT_VERSION >= QT_VERSION_CHECK(5, 14, 0))
            QStringList elements(hint.split(' ', Qt::SkipEmptyParts));
#else
            QStringList elements(hint.split(' ', QString::SkipEmptyParts));
#endif
            if (elements.size() <= 3) {
                qWarning() << "Unable to decode invalid remote action:" << hint;
            } else {
                int index = 0;
                action.insert(QStringLiteral("service"), elements.at(index++));
                action.insert(QStringLiteral("path"), elements.at(index++));
                action.insert(QStringLiteral("iface"), elements.at(index++));
                action.insert(QStringLiteral("method"), elements.at(index++));

                QVariantList args;
                while (index < elements.size()) {
                    const QString &arg(elements.at(index++));
                    const QByteArray buffer(QByteArray::fromBase64(arg.toUtf8()));

                    QDataStream stream(buffer);
                    QVariant var;
                    stream >> var;
                    args.append(var);
                }
                action.insert(QStringLiteral("arguments"), args);
            }
            action.insert(QStringLiteral("name"), actionName);
            action.insert(QStringLiteral("displayName"), displayName);

            const QString iconHintName = QString(HINT_REMOTE_ACTION_ICON_PREFIX) + actionName;
            const QString &iconHint = hints[iconHintName].toString();
            if (!iconHint.isEmpty()) {
                action.insert(QStringLiteral("icon"), iconHint);
            }

            const QString actionInputHintName = QString(HINT_REMOTE_ACTION_INPUT_PREFIX) + actionName;
            if (hints.contains(actionInputHintName)) {
                action.insert(QStringLiteral("input"), hints[actionInputHintName].toMap());
            }
            rv.append(action);
        }
    }

    return rv;
}

}

class NotificationPrivate : public NotificationData
{
    friend class Notification;

    NotificationPrivate()
        : NotificationData()
    {
    }

    NotificationPrivate(const NotificationData &data)
        : NotificationData(data)
        , remoteActions(decodeActionHints(actions, hints))
    {
    }

    QVariantMap firstRemoteAction() const
    {
        QVariantMap vm;
        const QVariant firstAction(remoteActions.value(0));
        if (!firstAction.isNull()) {
            vm = firstAction.value<QVariantMap>();
        }
        return vm;
    }

    void setFirstRemoteAction(const QVariantMap &vm_, Notification *q)
    {
        QVariantMap vm(vm_);
        QString name(vm["name"].value<QString>());
        if (name.isEmpty()) {
            vm.insert("name", QString::fromLatin1(DEFAULT_ACTION_NAME));
        }
        q->setRemoteActions(QVariantList() << vm);
    }

    QVariantList remoteActions;
};

/*!
    \qmltype Notification
    \inqmlmodule Nemo.Notifications
    \instantiates Notification
    \brief Allows notifications to be published

    The Notification type is a convenience type for using notifications
    based on the
    \l {https://specifications.freedesktop.org/notification-spec/latest/}
    {Desktop Notifications Specification} as implemented in Nemo.

    This type allows clients to create instances of notifications, which
    can be used to communicate to the home screen's Notification Manager via
    D-Bus.  This simplifies the process of creating, listing and closing
    notifications, since the necessary communications are handled by the
    type.

    Notification content can be specified by setting the various properties
    on an instance of the Notification type, or can be handled by providing
    a category, whose properties are automatically applied
    to matching notifications by the home screen's Notification Manager. Properties
    set in the notification instance will not be overwritten by values
    listed in the category.

    A minimal example of using this type from a QML application:

    \qml
    Button {
        Notification {
            id: notification

            summary: "Notification summary"
            body: "Notification body"
        }
        text: "Application notification" + (notification.replacesId ? " ID:" + notification.replacesId : "")
        onClicked: notification.publish()
    }
    \endqml

    When the button is clicked, a new notification is published to the
    notification manager, having the properties specified in the Notification
    object definition. Any properties specified by the definition file for
    the nominated category will be automatically applied by the notification
    manager during publication. The manager allocates an ID for the
    notification, and the instance is updated so that this ID is reflected
    in the \l replacesId property.

    When the user invokes the 'default' action on the notification, the
    \l clicked signal is emitted by the notification instance. If the
    application is no longer running at the relevant time, then the signal
    will be missed.

    A more exhaustive example of usage from a QML application:

    \qml
    Button {
        Notification {
            id: notification
            category: "x-nemo.example"
            appName: "Example App"
            appIcon: "/usr/share/example-app/icon-l-application"
            summary: "Notification summary"
            body: "Notification body"
            previewSummary: "Notification preview summary"
            previewBody: "Notification preview body"
            itemCount: 5
            timestamp: "2013-02-20 18:21:00"
            remoteActions: [ {
                "name": "default",
                "displayName": "Do something",
                "icon": "icon-s-do-it",
                "service": "org.nemomobile.example",
                "path": "/example",
                "iface": "org.nemomobile.example",
                "method": "doSomething",
                "arguments": [ "argument", 1 ]
            },{
                "name": "ignore",
                "displayName": "Ignore the problem",
                "icon": "icon-s-ignore",
                "input" : {
                    "label": "Please select",
                    "editable": true,
                    "choices": [ "Yes", "No", "Maybe" ]
                },
                "service": "org.nemomobile.example",
                "path": "/example",
                "iface": "org.nemomobile.example",
                "method": "ignore",
                "arguments": [ "argument", 1 ]
            } ]
            onClicked: console.log("Clicked")
            onClosed: console.log("Closed, reason: " + reason)
        }
        text: "Application notification" + (notification.replacesId ? " ID:" + notification.replacesId : "")
        onClicked: notification.publish()
    }
    \endqml

    In this case, the notification includes a specification for
    'remote actions', which are D-Bus commands that the notification
    manager may permit the user to invoke. When
    an action is invoked on the notification, the corresponding D-Bus
    command is formulated and invoked, which allows the application
    to be launched to handled the notification action, if required.
 */

/*!
    \class Notification
    \brief Allows notifications to be published
    \inmodule NemoNotifications
    \inheaderfile notification.h

    The Notification class is a convenience class for using notifications
    based on the
    \l {https://specifications.freedesktop.org/notification-spec/latest/}
    {Desktop Notifications Specification} as implemented in Nemo.

    This class allows clients to create instances of notifications, which
    can be used to communicate to the home screen's Notification Manager via
    D-Bus.  This simplifies the process of creating, listing and closing
    notifications, since the necessary communications are handled by the
    class.
 */

/*!
    \enum Notification::Urgency

    This enum type describes the urgency level of a notification.

    \value Low The notification is not urgent.
    \value Normal The notification is like most other notifications.
    \value Critical The notification is of urgent relevance to the user.
 */

/*!
    \enum Notification::CloseReason

    This enum type describes the reason given when a notification is reported as closed.

    \value Expired The notification expireTimeout period elapsed.
    \value DismissedByUser The notification was dismissed by user action.
    \value Closed The notification was closed programatically.
 */

/*!
    \fn Notification::Notification(QObject *)

    Constructs a new Notification, optionally using \a parent as the object parent.
 */
Notification::Notification(QObject *parent) :
    QObject(parent),
    d_ptr(new NotificationPrivate)
{
    d_ptr->hints.insert(HINT_URGENCY, static_cast<int>(Notification::Normal));
    connect(notificationManager(), SIGNAL(ActionInvoked(uint,QString)), this, SLOT(checkActionInvoked(uint,QString)));
    connect(notificationManager(), SIGNAL(NotificationClosed(uint,uint)), this, SLOT(checkNotificationClosed(uint,uint)));
    connect(notificationManager(), SIGNAL(InputTextSet(uint,QString)), this, SLOT(checkInputTextSet(uint,QString)));
}

/*!
    \fn Notification::Notification(const NotificationData &, QObject *)
    \internal
 */
Notification::Notification(const NotificationData &data, QObject *parent) :
    QObject(parent),
    d_ptr(new NotificationPrivate(data))
{
    connect(notificationManager(), SIGNAL(ActionInvoked(uint,QString)), this, SLOT(checkActionInvoked(uint,QString)));
    connect(notificationManager(), SIGNAL(NotificationClosed(uint,uint)), this, SLOT(checkNotificationClosed(uint,uint)));
    connect(notificationManager(), SIGNAL(InputTextSet(uint,QString)), this, SLOT(checkInputTextSet(uint,QString)));
}

/*!
    \fn Notification::~Notification()
    \internal
 */
Notification::~Notification()
{
    delete d_ptr;
}

/*!
    \qmlproperty string Notification::category

    The category whose properties should be applied to the notification by the Notification Manager.

    Properties defined by the category definition file will be applied to the notification,
    unless those properties are already set in the notification.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "category".
 */
/*!
    \property Notification::category

    The category whose properties should be applied to the notification by the Notification Manager.

    Properties defined by the category definition file will be applied to the notification,
    unless those properties are already set in the notification.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "category".
 */
QString Notification::category() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_CATEGORY).toString();
}

void Notification::setCategory(const QString &category)
{
    Q_D(Notification);
    if (category != this->category()) {
        d->hints.insert(HINT_CATEGORY, category);
        emit categoryChanged();
    }
}

/*!
    \qmlproperty string Notification::appName

    The application name associated with this notification, for display purposes.

    The application name should be the formal name, localized if appropriate.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "app_name".
 */
/*!
    \property Notification::appName

    The application name associated with this notification, for display purposes.

    The application name should be the formal name, localized if appropriate.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "app_name".
 */
QString Notification::appName() const
{
    Q_D(const Notification);
    return d->appName;
}

void Notification::setAppName(const QString &appName)
{
    Q_D(Notification);
    if (appName != this->appName()) {
        d->appName = appName;
        emit appNameChanged();
    }
}

/*!
    \qmlproperty string Notification::icon

    Icon of the notication. The value can be a URI, an absolute filesystem path,
    or a token to be interpreted by the theme image provider.

    Alternatively the iconData property may be used to set a decoded image.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "image-path".
 */
/*!
    \property Notification::icon

    Icon of the notication. The value can be a URI, an absolute filesystem path,
    or a token to be interpreted by the theme image provider.

    Alternatively the iconData property may be used to set a decoded image.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "image-path".

    \sa iconData
 */
QString Notification::icon() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_IMAGE_PATH).toString();
}

void Notification::setIcon(const QString &icon)
{
    Q_D(Notification);
    if (icon != this->icon()) {
        d->hints.insert(HINT_IMAGE_PATH, icon);
        emit iconChanged();
    }
}

/*!
    \qmlproperty int Notification::replacesId

    The ID that should be used to replace or remove this notification.

    If a notification is published with a non-zero ID, it will replace any existing notification
    with that ID, without alerting the user to any changes. An unpublished notification has a ID
    of zero. The ID is automatically updated to contain the published ID after publication is
    reported by the Notification Manager.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "replaces_id".
 */
/*!
    \property Notification::replacesId

    The ID that should be used to replace or remove this notification.

    If a notification is published with a non-zero ID, it will replace any existing notification
    with that ID, without alerting the user to any changes. An unpublished notification has a ID
    of zero. The ID is automatically updated to contain the published ID after publication is
    reported by the Notification Manager.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "replaces_id".
 */
uint Notification::replacesId() const
{
    Q_D(const Notification);
    return d->replacesId;
}

void Notification::setReplacesId(uint id)
{
    Q_D(Notification);
    if (d->replacesId != id) {
        d->replacesId = id;
        emit replacesIdChanged();
    }
}

/*!
    \qmlproperty string Notification::appIcon

    The icon for the application that this notification is associated with. The value can
    be a URI, an absolute filesystem path, or a token to be interpreted by the theme image provider.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "app_icon".
 */
/*!
    \property Notification::appIcon

    The icon for the application that this notification is associated with. The value can
    be a URI, an absolute filesystem path, or a token to be interpreted by the theme image provider.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "app_icon".
 */
QString Notification::appIcon() const
{
    Q_D(const Notification);
    return d->appIcon;
}

void Notification::setAppIcon(const QString &appIcon)
{
    Q_D(Notification);
    if (appIcon != this->appIcon()) {
        d->appIcon = appIcon;
        emit appIconChanged();
    }
}

/*!
    \qmlproperty string Notification::summary

    The summary text briefly describing the notification.
    The summary should give a brief, single-line description of the notification.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "summary".
 */
/*!
    \property Notification::summary

    The summary text briefly describing the notification.
    The summary should give a brief, single-line description of the notification.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "summary".
 */
QString Notification::summary() const
{
    Q_D(const Notification);
    return d->summary;
}

void Notification::setSummary(const QString &summary)
{
    Q_D(Notification);
    if (d->summary != summary) {
        d->summary = summary;
        emit summaryChanged();
    }
}

/*!
    \qmlproperty string Notification::body

    Optional detailed body text.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "body".
 */
/*!
    \property Notification::body

    Optional detailed body text.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "body".
 */
QString Notification::body() const
{
    Q_D(const Notification);
    return d->body;
}

void Notification::setBody(const QString &body)
{
    Q_D(Notification);
    if (d->body != body) {
        d->body = body;
        emit bodyChanged();
    }
}

/*!
    \qmlproperty enumeration Notification::urgency

    The urgency level of the notification. The value corresponds to one of:

    \list
    \li Notification.Low
    \li Notification.Normal
    \li Notification.Critical
    \endlist

    Urgency level is interpreted by the Notification Manager at publication. It may decide
    to display or to suppress display of the notification depending on the current user
    activity or device state, where notifications with \c Critical urgency are more likely
    to be displayed.

    Defaults to Normal urgency.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "urgency".
 */
/*!
    \property Notification::urgency

    The urgency level of the notification.

    Urgency level is interpreted by the Notification Manager at publication. It may decide
    to display or to suppress display of the notification depending on the current user
    activity or device state, where notifications with \c Critical urgency are more likely
    to be displayed.

    Defaults to Normal urgency.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "urgency".
 */
Notification::Urgency Notification::urgency() const
{
    Q_D(const Notification);
    // Clipping to bounds in case an invalid value is stored as a hint
    return static_cast<Urgency>(qMax(static_cast<int>(Low), qMin(static_cast<int>(Critical), d->hints.value(HINT_URGENCY).toInt())));
}

void Notification::setUrgency(Urgency urgency)
{
    Q_D(Notification);
    if (urgency != this->urgency()) {
        d->hints.insert(HINT_URGENCY, static_cast<int>(urgency));
        emit urgencyChanged();
    }
}

/*!
    \qmlproperty int Notification::expireTimeout

    The number of milliseconds after display at which the notification should be automatically closed.
    A value of zero indicates that the notification should not close automatically, while -1
    indicates that the notification manager should decide the expiration timeout.

    Defaults to -1.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "expire_timeout".
 */
/*!
    \property Notification::expireTimeout

    The number of milliseconds after display at which the notification should be automatically closed.
    A value of zero indicates that the notification should not close automatically, while -1
    indicates that the notification manager should decide the expiration timeout.

    Defaults to -1.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "expire_timeout".
 */
qint32 Notification::expireTimeout() const
{
    Q_D(const Notification);
    return d->expireTimeout;
}

void Notification::setExpireTimeout(qint32 milliseconds)
{
    Q_D(Notification);
    if (milliseconds != d->expireTimeout) {
        d->expireTimeout = milliseconds;
        emit expireTimeoutChanged();
    }
}

/*!
    \qmlproperty date Notification::timestamp

    The timestamp is typically associated with an event that the notification relates
    to, rather than for the creation of the notification itself. If not specified, the
    notification's timestamp will become the time of publification.

    This property is transmitted as the extension hint value "x-nemo-timestamp".
 */
/*!
    \property Notification::timestamp

    The timestamp is typically associated with an event that the notification relates
    to, rather than for the creation of the notification itself. If not specified, the
    notification's timestamp will become the time of publification.

    This property is transmitted as the extension hint value "x-nemo-timestamp".
 */
QDateTime Notification::timestamp() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_TIMESTAMP).toDateTime();
}

void Notification::setTimestamp(const QDateTime &timestamp)
{
    Q_D(Notification);
    if (timestamp != this->timestamp()) {
        d->hints.insert(HINT_TIMESTAMP, timestamp.toString(Qt::ISODate));
        emit timestampChanged();
    }
}

/*!
    \qmlproperty string Notification::previewSummary

    Summary text to be shown in the preview banner for the notification, if any.

    If this is not set it will automatically be set to the
    \l summary value when the notification is published.

    When the \l previewSummary or \c previewBody is specified, a preview of the notification
    will be generated by home screen at publication (unless the Notification Manager chooses
    to suppress the preview).

    This property is transmitted as the extension hint value "x-nemo-preview-summary".
 */
/*!
    \property Notification::previewSummary

    Summary text to be shown in the preview banner for the notification, if any.

    If this is not set it will automatically be set to the
    \l summary value when the notification is published.

    When the \l previewSummary or \c previewBody is specified, a preview of the notification
    will be generated by home screen at publication (unless the Notification Manager chooses
    to suppress the preview).

    This property is transmitted as the extension hint value "x-nemo-preview-summary".
 */
QString Notification::previewSummary() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_PREVIEW_SUMMARY).toString();
}

void Notification::setPreviewSummary(const QString &previewSummary)
{
    Q_D(Notification);
    if (previewSummary != this->previewSummary()) {
        d->hints.insert(HINT_PREVIEW_SUMMARY, previewSummary);
        emit previewSummaryChanged();
    }
}

/*!
    \qmlproperty string Notification::previewBody

    Body text to be shown in the preview banner for the notification, if any.

    If this is not set it will automatically be set to the
    \l body value when the notification is published.

    When the \l previewSummary or \c previewBody is specified, a preview of the notification
    will be generated by home screen at publication (unless the Notification Manager chooses
    to suppress the preview).

    This property is transmitted as the extension hint value "x-nemo-preview-body".
 */
/*!
    \property Notification::previewBody

    Body text to be shown in the preview banner for the notification, if any.

    If this is not set it will automatically be set to the
    \l body value when the notification is published.

    When the \l previewSummary or \c previewBody is specified, a preview of the notification
    will be generated by home screen at publication (unless the Notification Manager chooses
    to suppress the preview).

    This property is transmitted as the extension hint value "x-nemo-preview-body".
 */
QString Notification::previewBody() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_PREVIEW_BODY).toString();
}

void Notification::setPreviewBody(const QString &previewBody)
{
    Q_D(Notification);
    if (previewBody != this->previewBody()) {
        d->hints.insert(HINT_PREVIEW_BODY, previewBody);
        emit previewBodyChanged();
    }
}

/*!
    \qmlproperty string Notification::subText

    Sub-text of the notification, if any.

    This indicates some brief secondary information, such as the sender's email address in the
    case of a "new email" notification.

    This property is transmitted as the extension hint value "x-nemo-sub-text".
 */
/*!
    \property Notification::subText

    Sub-text of the notification, if any.

    This can indicate some brief secondary information, such as the sender's email address in the
    case of a "new email" notification.

    This property is transmitted as the extension hint value "x-nemo-sub-text".
 */
QString Notification::subText() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_SUB_TEXT).toString();
}

void Notification::setSubText(const QString &subText)
{
    Q_D(Notification);
    if (subText != this->subText()) {
        d->hints.insert(HINT_SUB_TEXT, subText);
        emit subTextChanged();
    }
}

/*!
    \qmlproperty string Notification::sound

    The file path of a sound to be played when the notification is shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "sound-file".
 */
/*!
    \property Notification::sound

    The file path of a sound to be played when the notification is shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "sound-file".
 */
QString Notification::sound() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_SOUND_FILE).toString();
}

void Notification::setSound(const QString &sound)
{
    Q_D(Notification);
    if (sound != this->sound()) {
        d->hints.insert(HINT_SOUND_FILE, sound);
        emit soundChanged();
    }
}

/*!
    \qmlproperty string Notification::soundName

    The name of a sound to be played when the notification is shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "sound-name",
    names following \l{https://specifications.freedesktop.org/sound-naming-spec/latest/index.html}{the freedesktop.org sound naming specification}.
    Sound name can be e.g. "message-new-instant" or "message-new-email".
 */
/*!
    \property Notification::soundName

    The name of a sound to be played when the notification is shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "sound-name",
    names following \l{https://specifications.freedesktop.org/sound-naming-spec/latest/index.html}{the freedesktop.org sound naming specification}.
    Sound name can be e.g. "message-new-instant" or "message-new-email".
 */
QString Notification::soundName() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_SOUND_NAME).toString();
}

void Notification::setSoundName(const QString &soundName)
{
    Q_D(Notification);
    if (soundName != this->soundName()) {
        d->hints.insert(HINT_SOUND_NAME, soundName);
        emit soundNameChanged();
    }
}

/*!
    \qmlproperty image Notification::iconData

    An image to be shown on the notification. N.B. this requires QImage typed value, not compatible with Image or such.

    Alternatively the \l icon property may be used to a set the URI of a persistent image file
    or a theme identifier for the icon.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "image-data".
 */

/*!
    \property Notification::iconData

    An image to be shown on the notification.

    Alternatively the \l icon property may be used to a set the URI of a persistent image file
    or a theme identifier for the icon.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "image-data".

    \sa icon
 */
QImage Notification::iconData() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_IMAGE_DATA).value<NotificationImage>();
}

void Notification::setIconData(const QImage &image)
{
    Q_D(Notification);
    if (image != this->iconData()) {
        d->hints.insert(HINT_IMAGE_DATA, QVariant::fromValue(NotificationImage(image)));
        emit iconDataChanged();
    }
}

/*!
    \qmlproperty int Notification::itemCount

    The number of items represented by the notification.
    For example, a single notification can represent four missed calls by setting the count to 4. Defaults to 1.

    This property is transmitted as the extension hint value "x-nemo-item-count".
 */
/*!
    \property Notification::itemCount

    The number of items represented by the notification.
    For example, a single notification can represent four missed calls by setting the count to 4. Defaults to 1.

    This property is transmitted as the extension hint value "x-nemo-item-count".
 */
int Notification::itemCount() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_ITEM_COUNT).toInt();
}

void Notification::setItemCount(int itemCount)
{
    Q_D(Notification);
    if (itemCount != this->itemCount()) {
        d->hints.insert(HINT_ITEM_COUNT, itemCount);
        emit itemCountChanged();
    }
}

/*!
    \qmlmethod void Notification::publish()

    Publishes the current state of the notification to the Notification Manager.

    If \l replacesId is zero, a new notification will be created and \l replacesId will be updated
    to contain that ID. Otherwise the existing notification with the given ID is updated with the
    new details.
*/
/*!
    \fn Notification::publish()

    Publishes the current state of the notification to the Notification Manager.

    If \l replacesId is zero, a new notification will be created and \l replacesId will be updated
    to contain that ID. Otherwise the existing notification with the given ID is updated with the
    new details.
 */
void Notification::publish()
{
    Q_D(Notification);

    // Validate the actions associated with the notification
    Q_FOREACH (const QVariant &action, d->remoteActions) {
        const QVariantMap &vm = action.value<QVariantMap>();
        int callbackParameters = 0;
        if (!vm["service"].value<QString>().isEmpty()) callbackParameters++;
        if (!vm["path"].value<QString>().isEmpty()) callbackParameters++;
        if (!vm["iface"].value<QString>().isEmpty()) callbackParameters++;
        if (!vm["method"].value<QString>().isEmpty()) callbackParameters++;

        if (vm["name"].value<QString>().isEmpty()
                || (callbackParameters != 0 && callbackParameters != 4)) {
            qWarning() << "Invalid remote action specification:" << action;
        }
    }

    // Ensure the ownership of this notification is recorded
    QVariantHash::iterator it = d->hints.find(HINT_OWNER);
    if (it == d->hints.end()) {
        d->hints.insert(HINT_OWNER, processName());
    }

    // Use the summary and body as fallback values for previewSummary and previewBody, unless the
    // preview values have explicitly been reset to invalid variants.
    QVariantHash hints = d->hints;
    auto setDefaultPreview = [&hints](const QString &hint, const QString &defaultValue) -> void {
        auto it = hints.find(hint);
        if (it == hints.end()) {
            hints.insert(hint, defaultValue);
        }
    };

    setDefaultPreview(HINT_PREVIEW_SUMMARY, d->summary);
    setDefaultPreview(HINT_PREVIEW_BODY, d->body);

    setReplacesId(notificationManager()->Notify(appName(), d->replacesId, appIcon(), d->summary, d->body,
                                                encodeActions(d->actions), hints, d->expireTimeout));
}


/*!
    \qmlmethod void Notification::close()

    Closes the notification identified by \l replacesId.
*/
/*!
    \fn Notification::close()

    Closes the notification identified by \l replacesId.
 */
void Notification::close()
{
    Q_D(Notification);
    if (d->replacesId != 0) {
        notificationManager()->CloseNotification(d->replacesId);
        setReplacesId(0);
    }
}

/*!
    \qmlsignal Notification::clicked()

    Emitted when the notification is activated by the user.

    Handling the \c clicked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published. A more robust solution is to register a 'remote action' with the
    Notification Manager, so that a handler can be started running and invoked
    to service the request.
    NB registering a D-Bus autostarted service might not be available for all the applications.

    \sa Notification::remoteActions
*/
/*!
    \fn void Notification::clicked()

    Emitted when the notification is activated by the user.

    Handling the \c clicked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published. A more robust solution is to register a 'remote action' with the
    Notification Manager, so that a handler can be started running and invoked
    to service the request.

    \sa remoteActions()
 */

/*!
    \qmlsignal Notification::actionInvoked(string name)

    Emitted when a notification action is activated by the user. \a name indicates the name of the invoked action.

    Handling the \c actionInvoked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published.
 */
/*!
    \fn void Notification::actionInvoked(const QString &name)

    Emitted when a notification action is activated by the user. \a name indicates the name of the invoked action.

    Handling the \c actionInvoked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published.
 */
/*!
    \qmlsignal Notification::inputActionInvoked(string name, string inputText)
    \internal

    Emitted when a notification action that requires input text is activated by the user. \a name indicates the name of the invoked action. \a inputText contains the user text.

    Handling the \c inputActionInvoked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published.
 */
/*!
    \fn void Notification::inputActionInvoked(const QString &name, const QString &inputText)
    \internal

    Emitted when a notification action that requires input text is activated by the user. \a name indicates the name of the invoked action. \a inputText contains the user text.

    Handling the \c inputActionInvoked signal is only effective if the process is running when the
    user activates the notification, which may occur long after the notification is
    published.
 */
void Notification::checkActionInvoked(uint id, QString actionKey)
{
    Q_D(Notification);
    if (id == d->replacesId) {
        foreach (const QVariant &action, d->remoteActions) {
            QVariantMap vm = action.value<QVariantMap>();
            const QString actionName = vm["name"].value<QString>();
            if (!actionName.isEmpty() && actionName == actionKey) {
                if (vm.contains("input")) { // Need input
                    const QVariantMap input = vm["input"].value<QVariantMap>();
                    if (d->inputText.isEmpty() // Input is empty
                        || (input.contains("choices") && !input["choices"].value<QStringList>().contains(d->inputText) // and not a valid choice 
                            && (!input.contains("editable") || input["editable"].toBool() == false))) { // and not editable
                        // TODO: Some sort of signal of rejection to the sender?
                        break;
                    }
                    emit inputActionInvoked(actionKey, d->inputText);
                } else {
                    emit actionInvoked(actionKey);
                }
                break;
            }
        }
        if (actionKey == DEFAULT_ACTION_NAME) {
            emit clicked();
        }
    }
}

void Notification::checkInputTextSet(uint id, const QString &inputText)
{
    Q_D(Notification);
    if (id == d->replacesId && inputText != d->inputText) {
        d->inputText = inputText;
    }
}

/*!
    \qmlsignal Notification::closed(uint reason)

    Emitted when the notification is reported closed by the notification manager.
    The \a reason value may be any one of:

    \list
    \li Notification.Expired
    \li Notification.DismissedByUser
    \li Notification.Closed
    \endlist
*/
/*!
    \fn void Notification::closed(uint reason)

    Emitted when the notification is reported closed by the notification manager.
    The \a reason value corresponds to a value defined by \l Notification::CloseReason.
 */
void Notification::checkNotificationClosed(uint id, uint reason)
{
    Q_D(Notification);
    if (id == d->replacesId) {
        emit closed(reason);
        setReplacesId(0);
    }
}

/*!
    \property Notification::remoteDBusCallServiceName
    \internal
 */
/*!
    \fn Notification::remoteDBusCallServiceName() const
    \internal
 */
QString Notification::remoteDBusCallServiceName() const
{
    Q_D(const Notification);
    QVariantMap vm(d->firstRemoteAction());
    return vm["service"].value<QString>();
}

/*!
    \fn Notification::setRemoteDBusCallServiceName(const QString &)
    \internal
 */
void Notification::setRemoteDBusCallServiceName(const QString &serviceName)
{
    Q_D(Notification);
    QVariantMap vm(d->firstRemoteAction());
    if (vm["service"].value<QString>() != serviceName) {
        vm.insert("service", serviceName);
        d->setFirstRemoteAction(vm, this);

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \property Notification::remoteDBusCallObjectPath
    \internal
 */
/*!
    \fn Notification::remoteDBusCallObjectPath() const
    \internal
 */
QString Notification::remoteDBusCallObjectPath() const
{
    Q_D(const Notification);
    QVariantMap vm(d->firstRemoteAction());
    return vm["path"].value<QString>();
}

/*!
    \fn Notification::setRemoteDBusCallObjectPath(const QString &)
    \internal
 */
void Notification::setRemoteDBusCallObjectPath(const QString &objectPath)
{
    Q_D(Notification);
    QVariantMap vm(d->firstRemoteAction());
    if (vm["path"].value<QString>() != objectPath) {
        vm.insert("path", objectPath);
        d->setFirstRemoteAction(vm, this);

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \property Notification::remoteDBusCallInterface
    \internal
 */
/*!
    \fn Notification::remoteDBusCallInterface() const
    \internal
 */
QString Notification::remoteDBusCallInterface() const
{
    Q_D(const Notification);
    QVariantMap vm(d->firstRemoteAction());
    return vm["iface"].value<QString>();
}

/*!
    \fn Notification::setRemoteDBusCallInterface(const QString &)
    \internal
 */
void Notification::setRemoteDBusCallInterface(const QString &interface)
{
    Q_D(Notification);
    QVariantMap vm(d->firstRemoteAction());
    if (vm["iface"].value<QString>() != interface) {
        vm.insert("iface", interface);
        d->setFirstRemoteAction(vm, this);

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \property Notification::remoteDBusCallMethodName
    \internal
 */
/*!
    \fn Notification::remoteDBusCallMethodName() const
    \internal
 */
QString Notification::remoteDBusCallMethodName() const
{
    Q_D(const Notification);
    QVariantMap vm(d->firstRemoteAction());
    return vm["method"].value<QString>();
}

/*!
    \fn Notification::setRemoteDBusCallMethodName(const QString &)
    \internal
 */
void Notification::setRemoteDBusCallMethodName(const QString &methodName)
{
    Q_D(Notification);
    QVariantMap vm(d->firstRemoteAction());
    if (vm["method"].value<QString>() != methodName) {
        vm.insert("method", methodName);
        d->setFirstRemoteAction(vm, this);

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \property Notification::remoteDBusCallArguments
    \internal
 */
/*!
    \fn Notification::remoteDBusCallArguments() const
    \internal
 */
QVariantList Notification::remoteDBusCallArguments() const
{
    Q_D(const Notification);
    QVariantMap vm(d->firstRemoteAction());
    return vm["arguments"].value<QVariantList>();
}

/*!
    \fn Notification::setRemoteDBusCallArguments(const QVariantList &)
    \internal
 */
void Notification::setRemoteDBusCallArguments(const QVariantList &arguments)
{
    Q_D(Notification);
    QVariantMap vm(d->firstRemoteAction());
    if (vm["arguments"].value<QVariantList>() != arguments) {
        vm.insert("arguments", arguments);
        d->setFirstRemoteAction(vm, this);

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \fn Notification::remoteDBusCallChanged()
    \internal
 */


/*!
    \qmlproperty list<variant> Notification::remoteActions

    The remote actions registered for potential invocation by this notification.

    Remote actions are specified as a list of objects having the properties
    'name', 'displayName, 'icon', 'service', 'path', 'iface', 'method',
    and 'arguments'. 'Name' is always a required property, and 'displayName'
    if the action is other than "default" or "app".

    If D-Bus callback is needed, then 'service', 'path, 'iface, 'method', and optionally
    'arguments' should be set.

    For example:

    \qml
    Notification {
        remoteActions: [ {
            "name": "default",
            "displayName": "Do something",
            "icon": "icon-s-do-it",
            "service": "org.nemomobile.example",
            "path": "/example",
            "iface": "org.nemomobile.example",
            "method": "doSomething",
            "arguments": [ "argument", 1 ]
        } ]
    }
    \endqml

    \qml
    Notification {
        remoteAction: [ {
           "name": "default"
        }, {
           "name": "extraAction",
           "displayName": "Extra action (no callback)"
        } ]
    }
    \endqml

    \note the action named "default" will be invoked when the user activates the main notification item.
    If the user activates a notification group, the action named "app" will be invoked, if that action is
    shared by all members of the group.

    This property is transmitted as the \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "actions" and the extension hint value "x-nemo-remote-action-<name>".
 */
/*!
    \property Notification::remoteActions

    The remote actions registered for potential invocation by this notification.

    Remote actions may specify D-Bus calls to be emitted by the Notification Manager when a notification
    is activated by the user.  \l{remoteAction()}
    {remoteAction} describes the format of a remote action specification.

    \note the action named "default" will be invoked when the user activates the main notification item.
    If the user activates a notification group, the action named "app" will be invoked, if that action is
    shared by all members of the group.

    This property is transmitted as the \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s09.html#command-notify}{Notify} parameter "actions" and the extension hint value "x-nemo-remote-action-<name>".

    \sa remoteAction()
 */
QVariantList Notification::remoteActions() const
{
    Q_D(const Notification);
    return d->remoteActions;
}

void Notification::setRemoteActions(const QVariantList &remoteActions)
{
    Q_D(Notification);
    if (remoteActions != d->remoteActions) {
        // Remove any existing actions
        foreach (const QVariant &action, d->remoteActions) {
            QVariantMap vm = action.value<QVariantMap>();
            const QString actionName = vm["name"].value<QString>();
            if (!actionName.isEmpty()) {
                d->hints.remove(QString(HINT_REMOTE_ACTION_PREFIX) + actionName);
                for (int i = 0; i < d->actions.count(); ++i) {
                    if (d->actions.at(i).name == actionName) {
                        d->actions.removeAt(i);
                        break;
                    }
                }
            }
        }

        // Add the new actions and their associated hints
        d->remoteActions = remoteActions;

        QPair<QList<NotificationData::ActionInfo>, QVariantHash> actionHints = encodeActionHints(remoteActions);

        for (const NotificationData::ActionInfo &actionInfo : actionHints.first) {
            d->actions.append(actionInfo);
        }

        QVariantHash::const_iterator hit = actionHints.second.constBegin(), hend = actionHints.second.constEnd();
        for ( ; hit != hend; ++hit) {
            d->hints.insert(hit.key(), hit.value());
        }

        emit remoteActionsChanged();
        emit remoteDBusCallChanged();
    }
}

/*!
    \fn Notification::setRemoteAction(const QVariant &)
    \internal
 */

/*!
    \qmlproperty string Notification::origin

    A property indicating the origin of the notification.

    The origin hint can be used to associate an external property with a notification, separate
    from the intermediary that reports the notification. For example, a notification of a new
    email is created and handled by an email client application, but notionally originates at
    the sender's email address.

    This property is transmitted as the extension hint value "x-nemo-origin".

    \obsolete
*/
/*!
    \property Notification::origin

    A property indicating the origin of the notification.

    The origin hint can be used to associate an external property with a notification, separate
    from the intermediary that reports the notification. For example, a notification of a new
    email is created and handled by an email client application, but notionally originates at
    the sender's email address.

    This property is transmitted as the extension hint value "x-nemo-origin".

    \obsolete
*/
QString Notification::origin() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_ORIGIN).toString();
}

void Notification::setOrigin(const QString &origin)
{
    Q_D(Notification);
    if (origin != this->origin()) {
        qWarning() << "Notification sets deprecated origin property to" << origin << ", use subText instead";
        d->hints.insert(HINT_ORIGIN, origin);
        emit originChanged();
    }
}

/*!
    \qmlproperty int Notification::maxContentLines

    A property suggesting the maximum amount of content to display for the notification.
    The content lines include the summary line, so a single-line notification does
    not display any body text.

    This property is transmitted as the extension hint value "x-nemo-max-content-lines".
*/
/*!
    \property Notification::maxContentLines

    A property suggesting the maximum amount of content to display for the notification.
    The content lines include the summary line, so a single-line notification does
    not display any body text.

    This property is transmitted as the extension hint value "x-nemo-max-content-lines".
*/
int Notification::maxContentLines() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_MAX_CONTENT_LINES).toInt();
}

void Notification::setMaxContentLines(int max)
{
    Q_D(Notification);
    if (max != this->maxContentLines()) {
        qWarning() << "Notification::maxContentLines property is deprecated";
        d->hints.insert(HINT_MAX_CONTENT_LINES, max);
        emit maxContentLinesChanged();
    }
}

// "is" prefix to avoid Javascript reserved word
/*!
    \qmlproperty int Notification::isTransient

    A property suggesting that notification should be only briefly shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "transient".
*/
/*!
    \property Notification::isTransient

    A property suggesting that notification should be only briefly shown.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "transient".
*/
bool Notification::isTransient() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_TRANSIENT).toBool();
}

void Notification::setIsTransient(bool value)
{
    Q_D(Notification);
    if (value != this->isTransient()) {
        d->hints.insert(HINT_TRANSIENT, value);
        emit isTransientChanged();
    }
}

/*!
    \qmlproperty int Notification::resident

    A resident property is not automatically closed when an action is invoked. It remains until explicitly removed by the user or by the sender.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "resident".
*/
/*!
    \property Notification::resident

    A resident property is not automatically closed when an action is invoked. It remains until explicitly removed by the user or by the sender.

    This property is transmitted as the standard \l{https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html}{hint value} "resident".
*/
bool Notification::resident() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_RESIDENT).toBool();
}

void Notification::setResident(bool value)
{
    Q_D(Notification);
    if (value != this->resident()) {
        d->hints.insert(HINT_RESIDENT, value);
        emit residentChanged();
    }
}

/*!
    \qmlproperty var Notification::progress

    Property containing the progress the notification represent. Value can be undefined for no progress,
    Notification.ProgressIndeterminate for indeterminate state or real between 0.0 and 1.0 to represent progress percentage.
*/
/*!
    \property Notification::progress

    Property containing the progress the notification represent. Value can be undefined for no progress,
    Notification::ProgressIndeterminate for indeterminate state or real between 0.0 and 1.0 to represent progress percentage.
*/

QVariant Notification::progress() const
{
    Q_D(const Notification);
    return d->hints.value(HINT_PROGRESS);
}

void Notification::setProgress(const QVariant &value)
{
    Q_D(Notification);

    if (value.isNull()) {
        resetProgress();
    } else {
        // D-Bus doesn't support float types so force to double to avoid apps getting surprised
        QVariant filteredValue(value.toDouble());
        if (filteredValue != this->progress()) {
            d->hints.insert(HINT_PROGRESS, filteredValue);
            emit progressChanged();
        }
    }
}

void Notification::resetProgress()
{
    Q_D(Notification);
    if (d->hints.contains(HINT_PROGRESS)) {
        d->hints.remove(HINT_PROGRESS);
        emit progressChanged();
    }
}

/*!
    \fn Notification::hintValue(const QString &) const

    Returns the value of the hint named \a hint.
 */
QVariant Notification::hintValue(const QString &hint) const
{
    Q_D(const Notification);
    return d->hints.value(hint);
}

/*!
    \fn Notification::setHintValue(const QString &, const QVariant &)

    Sets the value of the hint named \a hint to \a value.
 */
void Notification::setHintValue(const QString &hint, const QVariant &value)
{
    Q_D(Notification);
    if (!value.isValid()) {
        // to consider: filter out everything that doesn't serialize to d-bus?
        qWarning() << "Invalid value given for notification hint" << hint;
        return;
    }
    d->hints.insert(hint, value);
}

/*!
    \fn Notification::notifications()

    Returns a list of existing notifications whose 'x-nemo-owner' hint value
    matches the process name of the running process.

    All notifications produced by calling \l publish() are set to contain a hint
    'x-nemo-owner' with the value of process name of the running process (unless
    that hint is already specified).  This allows previously generated notifications
    to be easily retrieved via this function.

    The returned objects are instances of the \c Notification class. The caller takes ownership and
    should destroy them when they are no longer required.
 */
QList<QObject*> Notification::notifications()
{
    // By default, only the notifications owned by us are returned
    return notifications(processName());
}

/*!
    \fn Notification::notifications(const QString &)

    Returns a list of existing notifications whose 'x-nemo-owner' hint value
    matches \a owner.

    The returned objects are instances of the \c Notification class. The caller takes ownership and
    should destroy them when they are no longer required.
 */
QList<QObject*> Notification::notifications(const QString &owner)
{
    QList<NotificationData> notifications = notificationManager()->GetNotifications(owner);
    QList<QObject*> objects;
    foreach (const NotificationData &notification, notifications) {
        objects.append(createNotification(notification, notificationManager()));
    }
    return objects;
}

/*!
    \fn Notification::notificationsByCategory(const QString &)

    Returns a list of existing notifications whose 'category' hint value
    matches \a category. This requires privileged access rights from the caller.

    The returned objects are instances of the \c Notification class. The caller takes ownership and
    should destroy them when they are no longer required.
 */
QList<QObject *> Notification::notificationsByCategory(const QString &category)
{
    QList<NotificationData> notifications = notificationManager()->GetNotificationsByCategory(category);
    QList<QObject*> objects;
    foreach (const NotificationData &notification, notifications) {
        objects.append(createNotification(notification, notificationManager()));
    }
    return objects;
}

/*!
    \fn Notification::remoteAction(const QString &, const QString &, const QString &, const QString &, const QString &, const QString &, const QVariantList &)

    Helper function to assemble an object specifying a remote action, potentially to be invoked via D-Bus.

    If \a service, \a path, \a iface, \a method, and optionally \a arguments are set, the action
    can trigger a D-Bus callback when activated by the user.

    \list
    \li \a name: the name of the action. "default" for the whole notification icon. If empty, will generate a name
    \li \a displayName: the name of the action to be displayed to user. May not get displayed for "default", in which case it can be empty.
    \li \a service: the name of the D-Bus service to be invoked
    \li \a path: the object path to be invoked via D-Bus
    \li \a iface: the interface to be invoked via D-Bus
    \li \a method: the method of the interface to be invoked via D-Bus
    \li \a arguments: the optional arguments to be passed to the method invoked via D-Bus
    \endlist
*/
QVariant Notification::remoteAction(const QString &name, const QString &displayName,
                                    const QString &service, const QString &path, const QString &iface,
                                    const QString &method, const QVariantList &arguments)
{
    QVariantMap action;
    static quint32 autoActionNameCounter = 0;

    const QString &actionName = name.isEmpty()
            ? QStringLiteral("action_%1_%2").arg(time(nullptr)).arg(++autoActionNameCounter)
            : name;
    action.insert(QStringLiteral("name"), actionName);

    if (!displayName.isEmpty()) {
        action.insert(QStringLiteral("displayName"), displayName);
    }
    if (!service.isEmpty()) {
        action.insert(QStringLiteral("service"), service);
    }
    if (!path.isEmpty()) {
        action.insert(QStringLiteral("path"), path);
    }
    if (!iface.isEmpty()) {
        action.insert(QStringLiteral("iface"), iface);
    }
    if (!method.isEmpty()) {
        action.insert(QStringLiteral("method"), method);
    }
    if (!arguments.isEmpty()) {
        action.insert(QStringLiteral("arguments"), arguments);
    }

    return action;
}

/*!
    \fn Notification::actionSetInputFormat(QVariant &, QString &, bool, const QStringList &)
    \internal

    Helper function to add details to a remote action to be invoked via D-Bus. 

    \list
    \li \a action: QVariantMap created by Notification::remoteAction
    \li \a label: QString caption for the input field
    \li \a editable: whether the input can be freetext typed or edited by the user
    \li \a choices: A QStringList of options to select. If editable is also set, then the user may edit their selection.
    \endlist
*/
QVariant Notification::actionSetInputFormat(QVariant &action, QString &label, bool editable, const QStringList &choices)
{
    QVariantMap vm = action.value<QVariantMap>();
    QVariantMap input;
    input.insert(QStringLiteral("label"), label);
    input.insert(QStringLiteral("editable"), editable);
    input.insert(QStringLiteral("choices"), choices);
    vm.insert(QStringLiteral("input"), input);
    return vm;
}

/*!
    \fn Notification::createNotification(const NotificationData &, QObject *)
    \internal
 */
Notification *Notification::createNotification(const NotificationData &data, QObject *parent)
{
    return new Notification(data, parent);
}

QDBusArgument &operator<<(QDBusArgument &argument, const NotificationData &data)
{
    argument.beginStructure();
    argument << data.appName;
    argument << data.replacesId;
    argument << data.appIcon;
    argument << data.summary;
    argument << data.body;
    argument << encodeActions(data.actions);
    argument << data.hints;
    argument << data.expireTimeout;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, NotificationData &data)
{
    QStringList tempStringList;

    argument.beginStructure();
    argument >> data.appName;
    argument >> data.replacesId;
    argument >> data.appIcon;
    argument >> data.summary;
    argument >> data.body;
    argument >> tempStringList;
    argument >> data.hints;
    argument >> data.expireTimeout;
    argument.endStructure();

    data.actions = decodeActions(tempStringList);

    return argument;
}

bool NotificationConnectionManager::useDBusConnection(const QDBusConnection &conn)
{
    if (connMgr()->proxy.isNull()) {
        if (conn.isConnected()) {
            connMgr()->dBusConnection.reset(new QDBusConnection(conn));
            return true;
        } else {
            qWarning() << "Supplied DBus connection is not connected.";
        }
    } else {
        qWarning() << "Cannot override DBus connection - notifications already exist.";
    }
    return false;
}

#include "moc_notification.cpp"
