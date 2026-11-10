// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Share 1.0's native types (clean room; names from the public
// Sailfish Share documentation, the D-Bus contract from the BSD-licensed
// sailfishshare-components package; see keel/silica/COMPATIBILITY.md):
//   ShareResource  one shared item as a ShareProvider receives it
//   ShareProvider  makes the app a share target: the system share dialog
//                  calls org.sailfishos.share.share(a{sv}) on the app's
//                  /share/<method> object on the session bus
//   KeelShareService (Keel internal) hands a ShareAction's configuration to
//                  the system share dialog, org.sailfishos.share

#ifndef KEEL_SHARE_H
#define KEEL_SHARE_H

#include <QObject>
#include <QQmlEngine>
#include <QQmlParserStatus>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

class ShareResource : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("ShareResource objects come from ShareProvider.triggered")
    Q_PROPERTY(ResourceType type READ type CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString data READ data CONSTANT)
    Q_PROPERTY(QString filePath READ filePath CONSTANT)

public:
    enum ResourceType { StringDataType = 1, FilePathType = 2 };
    Q_ENUM(ResourceType)

    ShareResource(ResourceType type, QString name, QString data, QString filePath, QObject *parent);

    ResourceType type() const { return m_type; }
    QString name() const { return m_name; }
    QString data() const { return m_data; }
    QString filePath() const { return m_filePath; }

private:
    ResourceType m_type;
    QString m_name;
    QString m_data;
    QString m_filePath;
};

class ShareProvider : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString method READ method WRITE setMethod NOTIFY methodChanged)
    Q_PROPERTY(bool registerName READ registerName WRITE setRegisterName NOTIFY registerNameChanged)
    Q_PROPERTY(QStringList capabilities READ capabilities WRITE setCapabilities NOTIFY capabilitiesChanged)

public:
    explicit ShareProvider(QObject *parent = nullptr);
    ~ShareProvider() override;

    QString method() const { return m_method; }
    void setMethod(const QString &method);
    bool registerName() const { return m_registerName; }
    void setRegisterName(bool registerName);
    QStringList capabilities() const { return m_capabilities; }
    void setCapabilities(const QStringList &capabilities);

    void classBegin() override { }
    void componentComplete() override;

    // The D-Bus call; returns an error name, or an empty string when the
    // configuration was accepted and triggered() emitted.
    QString share(const QVariantMap &configuration);

    // The session bus name ShareProvider registers with registerName: the
    // app's Sailjail name, <organization>.<application>.
    static QString serviceName();

signals:
    void methodChanged();
    void registerNameChanged();
    void capabilitiesChanged();
    void triggered(const QVariantList &resources);

private:
    void registerObject();
    void unregisterObject();
    bool accepts(const QString &mimeType) const;
    std::unique_ptr<ShareResource> resourceFrom(const QVariant &value, QString *error);

    QString m_method;
    QString m_registeredPath;
    QStringList m_capabilities;
    QStringList m_receivedFiles;
    QList<ShareResource *> m_resources;
    bool m_registerName = false;
    bool m_nameRegistered = false;
    bool m_complete = false;
};

class KeelShareService : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit KeelShareService(QObject *parent = nullptr);

    // Whether the system share dialog (org.sailfishos.share) is running or
    // can be started on the session bus.
    Q_INVOKABLE bool available() const;
    // Opens the system share dialog with a ShareAction configuration
    // (resources, mimeType, title, selectedTransferMethodInfo).
    Q_INVOKABLE bool share(const QVariantMap &configuration);
};

#endif
