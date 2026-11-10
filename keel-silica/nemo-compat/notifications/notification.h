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

#ifndef NOTIFICATION_H
#define NOTIFICATION_H

#include <notificationexport.h>

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDateTime>
#include <QVariant>
#include <QVariantList>

struct NotificationData;

class NotificationManagerProxy;
class NotificationPrivate;

class NEMO_QML_PLUGIN_NOTIFICATIONS_EXPORT Notification : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY categoryChanged)
    Q_PROPERTY(QString appName READ appName WRITE setAppName NOTIFY appNameChanged)
    Q_PROPERTY(quint32 replacesId READ replacesId WRITE setReplacesId NOTIFY replacesIdChanged)
    Q_PROPERTY(QString icon READ icon WRITE setIcon NOTIFY iconChanged)
    Q_PROPERTY(QString appIcon READ appIcon WRITE setAppIcon NOTIFY appIconChanged)
    Q_PROPERTY(QString summary READ summary WRITE setSummary NOTIFY summaryChanged)
    Q_PROPERTY(QString body READ body WRITE setBody NOTIFY bodyChanged)
    Q_PROPERTY(Urgency urgency READ urgency WRITE setUrgency NOTIFY urgencyChanged)
    Q_PROPERTY(qint32 expireTimeout READ expireTimeout WRITE setExpireTimeout NOTIFY expireTimeoutChanged)
    Q_PROPERTY(QDateTime timestamp READ timestamp WRITE setTimestamp NOTIFY timestampChanged)
    Q_PROPERTY(QString previewSummary READ previewSummary WRITE setPreviewSummary NOTIFY previewSummaryChanged)
    Q_PROPERTY(QString previewBody READ previewBody WRITE setPreviewBody NOTIFY previewBodyChanged)
    Q_PROPERTY(QString subText READ subText WRITE setSubText NOTIFY subTextChanged)
    Q_PROPERTY(QString sound READ sound WRITE setSound NOTIFY soundChanged)
    Q_PROPERTY(QString soundName READ soundName WRITE setSoundName NOTIFY soundNameChanged)
    Q_PROPERTY(QImage iconData READ iconData WRITE setIconData NOTIFY iconDataChanged)
    Q_PROPERTY(int itemCount READ itemCount WRITE setItemCount NOTIFY itemCountChanged)
    Q_PROPERTY(QVariantList remoteActions READ remoteActions WRITE setRemoteActions NOTIFY remoteActionsChanged)
    Q_PROPERTY(bool isTransient READ isTransient WRITE setIsTransient NOTIFY isTransientChanged)
    Q_PROPERTY(bool resident READ resident WRITE setResident NOTIFY residentChanged)
    Q_PROPERTY(QVariant progress READ progress WRITE setProgress RESET resetProgress NOTIFY progressChanged)
    // deprecated properties
    Q_PROPERTY(QString remoteDBusCallServiceName READ remoteDBusCallServiceName WRITE setRemoteDBusCallServiceName NOTIFY remoteDBusCallChanged)
    Q_PROPERTY(QString remoteDBusCallObjectPath READ remoteDBusCallObjectPath WRITE setRemoteDBusCallObjectPath NOTIFY remoteDBusCallChanged)
    Q_PROPERTY(QString remoteDBusCallInterface READ remoteDBusCallInterface WRITE setRemoteDBusCallInterface NOTIFY remoteDBusCallChanged)
    Q_PROPERTY(QString remoteDBusCallMethodName READ remoteDBusCallMethodName WRITE setRemoteDBusCallMethodName NOTIFY remoteDBusCallChanged)
    Q_PROPERTY(QVariantList remoteDBusCallArguments READ remoteDBusCallArguments WRITE setRemoteDBusCallArguments NOTIFY remoteDBusCallChanged)
    Q_PROPERTY(QString origin READ origin WRITE setOrigin NOTIFY originChanged)
    Q_PROPERTY(int maxContentLines READ maxContentLines WRITE setMaxContentLines NOTIFY maxContentLinesChanged)
    Q_ENUMS(Urgency)
    Q_ENUMS(CloseReason)
    Q_ENUMS(Progress)

public:
    enum Urgency { Low = 0, Normal = 1, Critical = 2 };
    enum CloseReason { Expired = 0, DismissedByUser = 1, Closed = 2 };
    enum Progress { ProgressIndeterminate = -1 };

    explicit Notification(QObject *parent = 0);
    virtual ~Notification();

    QString category() const;
    void setCategory(const QString &category);

    QString appName() const;
    void setAppName(const QString &appName);

    quint32 replacesId() const;
    void setReplacesId(quint32 id);

    QString icon() const;
    void setIcon(const QString &icon);

    QString appIcon() const;
    void setAppIcon(const QString &appIcon);

    QString summary() const;
    void setSummary(const QString &summary);

    QString body() const;
    void setBody(const QString &body);

    Urgency urgency() const;
    void setUrgency(Urgency urgency);

    qint32 expireTimeout() const;
    void setExpireTimeout(qint32 milliseconds);

    QDateTime timestamp() const;
    void setTimestamp(const QDateTime &timestamp);

    QString previewSummary() const;
    void setPreviewSummary(const QString &previewSummary);

    QString previewBody() const;
    void setPreviewBody(const QString &previewBody);

    QString subText() const;
    void setSubText(const QString &subText);

    QString sound() const;
    void setSound(const QString &sound);

    QString soundName() const;
    void setSoundName(const QString &soundName);

    QImage iconData() const;
    void setIconData(const QImage &image);

    int itemCount() const;
    void setItemCount(int itemCount);

    // Obsoleted 'remoteDBusCall...' functions:
    QString remoteDBusCallServiceName() const;
    void setRemoteDBusCallServiceName(const QString &serviceName);

    QString remoteDBusCallObjectPath() const;
    void setRemoteDBusCallObjectPath(const QString &objectPath);

    QString remoteDBusCallInterface() const;
    void setRemoteDBusCallInterface(const QString &interface);

    QString remoteDBusCallMethodName() const;
    void setRemoteDBusCallMethodName(const QString &methodName);

    QVariantList remoteDBusCallArguments() const;
    void setRemoteDBusCallArguments(const QVariantList &arguments);

    // Obsoletes the set of remoteDBusCall... properties
    QVariantList remoteActions() const;
    void setRemoteActions(const QVariantList &remoteActions);
    inline void setRemoteAction(const QVariant &remoteAction) { setRemoteActions(QVariantList() << remoteAction); }

    // Obsolete
    QString origin() const;
    void setOrigin(const QString &origin);

    // Obsolete
    int maxContentLines() const;
    void setMaxContentLines(int max);

    bool isTransient() const;
    void setIsTransient(bool value);

    bool resident() const;
    void setResident(bool value);

    QVariant progress() const;
    void setProgress(const QVariant &value);
    void resetProgress();

    QVariant hintValue(const QString &hint) const;
    void setHintValue(const QString &hint, const QVariant &value);

    Q_INVOKABLE void publish();
    Q_INVOKABLE void close();

    Q_INVOKABLE static QList<QObject*> notifications();
    Q_INVOKABLE static QList<QObject*> notifications(const QString &owner);
    Q_INVOKABLE static QList<QObject*> notificationsByCategory(const QString &category);

    Q_INVOKABLE static QVariant remoteAction(const QString &name, const QString &displayName,
                                             const QString &service = QString(), const QString &path = QString(), const QString &iface = QString(),
                                             const QString &method = QString(), const QVariantList &arguments = QVariantList());
    static QVariant actionSetInputFormat(QVariant &action, QString &label, bool editable, const QStringList &choices = QStringList());

signals:
    void clicked();
    void actionInvoked(const QString &name);
    void inputActionInvoked(const QString &name, const QString &inputText);
    void closed(uint reason);
    void categoryChanged();
    void appNameChanged();
    void replacesIdChanged();
    void iconChanged();
    void appIconChanged();
    void summaryChanged();
    void subTextChanged();
    void bodyChanged();
    void urgencyChanged();
    void expireTimeoutChanged();
    void timestampChanged();
    void previewSummaryChanged();
    void previewBodyChanged();
    void soundChanged();
    void soundNameChanged();
    void iconDataChanged();
    void itemCountChanged();
    void remoteActionsChanged();
    void remoteDBusCallChanged();
    void originChanged();
    void maxContentLinesChanged();
    void isTransientChanged();
    void residentChanged();
    void progressChanged();

private slots:
    void checkActionInvoked(uint id, QString actionKey);
    void checkNotificationClosed(uint id, uint reason);
    void checkInputTextSet(uint id, const QString &inputText);

private:
    NotificationPrivate * const d_ptr;
    Q_DECLARE_PRIVATE(Notification)

    Notification(const NotificationData &data, QObject *parent = 0);

    static Notification *createNotification(const NotificationData &data, QObject *parent = 0);
};

#endif // NOTIFICATION_H
