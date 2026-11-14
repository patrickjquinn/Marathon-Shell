// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRET_H
#define LIBSAILFISHSECRETS_SECRET_H

#include "Secrets/secretsglobal.h"

#include <QtCore/QMetaType>
#include <QtCore/QString>
#include <QtCore/QByteArray>
#include <QtCore/QVector>
#include <QtCore/QHash>
#include <QtCore/QMap>
#include <QtCore/QSharedDataPointer>

namespace Sailfish {

namespace Secrets {

class SecretIdentifierPrivate;
class SecretPrivate;
class SAILFISH_SECRETS_API Secret
{
    Q_GADGET
    Q_PROPERTY(QString name READ name WRITE setName)
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName)
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName)
    Q_PROPERTY(QString type READ type WRITE setType)
    Q_PROPERTY(QByteArray data READ data WRITE setData)
    Q_PROPERTY(QStringList filterDataFields READ filterDataFields)

public:
    static const QString FilterDataFieldType;
    static const QString TypeUnknown;
    static const QString TypeBlob;
    static const QString TypeCryptoKey;
    static const QString TypeCryptoCertificate;
    static const QString TypeUsernamePassword;

    class Identifier {
    public:
        Identifier();
        explicit Identifier(const QString &name, const QString &collectionName, const QString &storagePluginName);
        Identifier(const Sailfish::Secrets::Secret::Identifier &other);
        ~Identifier();

        Identifier &operator=(const Sailfish::Secrets::Secret::Identifier &other);

        bool isValid() const;
        bool identifiesStandaloneSecret() const;

        QString name() const;
        void setName(const QString &name);
        QString collectionName() const;
        void setCollectionName(const QString &collectionName);
        QString storagePluginName() const;
        void setStoragePluginName(const QString &storagePluginName);
    private:
        QSharedDataPointer<SecretIdentifierPrivate> d_ptr;
        friend class SecretIdentifierPrivate;
    };

    class FilterData : public QMap<QString,QString> {
    // this exists solely to prevent Qt's metatype system from erroring on duplicate registration
    public:
        FilterData(const QMap<QString,QString> &v) : QMap<QString,QString>(v) {}
        FilterData() = default;
        FilterData(const Sailfish::Secrets::Secret::FilterData &) = default;
        FilterData(Sailfish::Secrets::Secret::FilterData &&) = default;
        FilterData &operator=(const Sailfish::Secrets::Secret::FilterData &) = default;
    };

    Secret();
    Secret(const Secret &other);
    explicit Secret(const QString &name, const QString &collection, const QString &storagePlugin);
    explicit Secret(const Secret::Identifier &ident);
    explicit Secret(const QByteArray &blob, const Sailfish::Secrets::Secret::FilterData &filterData = Sailfish::Secrets::Secret::FilterData());
    ~Secret();

    Secret &operator=(const Sailfish::Secrets::Secret &other);

    QString type() const;
    void setType(const QString &type);

    Sailfish::Secrets::Secret::Identifier identifier() const;
    void setIdentifier(const Sailfish::Secrets::Secret::Identifier &identifier);

    QString name() const;
    void setName(const QString &name);
    QString collectionName() const;
    void setCollectionName(const QString &cname);
    QString storagePluginName() const;
    void setStoragePluginName(const QString &pname);

    QByteArray data() const;
    void setData(const QByteArray &data);

    Sailfish::Secrets::Secret::FilterData filterData() const;
    void setFilterData(const Sailfish::Secrets::Secret::FilterData &data);
    QStringList filterDataFields() const;
    Q_INVOKABLE QString filterData(const QString &field) const;
    Q_INVOKABLE void setFilterData(const QString &field, const QString &value);
    Q_INVOKABLE bool hasFilterData(const QString &field) const;

private:
    QSharedDataPointer<SecretPrivate> d_ptr;
    friend class SecretPrivate;
};

bool operator==(const Sailfish::Secrets::Secret::Identifier &lhs, const Sailfish::Secrets::Secret::Identifier &rhs) SAILFISH_SECRETS_API;
bool operator!=(const Sailfish::Secrets::Secret::Identifier &lhs, const Sailfish::Secrets::Secret::Identifier &rhs) SAILFISH_SECRETS_API;
bool operator<(const Sailfish::Secrets::Secret::Identifier &lhs, const Sailfish::Secrets::Secret::Identifier &rhs) SAILFISH_SECRETS_API;
bool operator==(const Sailfish::Secrets::Secret &lhs, const Sailfish::Secrets::Secret &rhs) SAILFISH_SECRETS_API;
bool operator!=(const Sailfish::Secrets::Secret &lhs, const Sailfish::Secrets::Secret &rhs) SAILFISH_SECRETS_API;
bool operator<(const Sailfish::Secrets::Secret &lhs, const Sailfish::Secrets::Secret &rhs) SAILFISH_SECRETS_API;

} // namespace Secrets

} // namespace Sailfish

Q_DECLARE_METATYPE(Sailfish::Secrets::Secret::FilterData);
Q_DECLARE_TYPEINFO(Sailfish::Secrets::Secret::FilterData, Q_MOVABLE_TYPE);
Q_DECLARE_METATYPE(Sailfish::Secrets::Secret::Identifier);
Q_DECLARE_TYPEINFO(Sailfish::Secrets::Secret::Identifier, Q_MOVABLE_TYPE);
Q_DECLARE_METATYPE(Sailfish::Secrets::Secret);
Q_DECLARE_TYPEINFO(Sailfish::Secrets::Secret, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHSECRETS_SECRET_H
