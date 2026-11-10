// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/cryptomanager.h"
#include "Crypto/result.h"
#include "Crypto/key.h"
#include "Crypto/plugininfo.h"
#include "Crypto/cipherrequest.h"
#include "Crypto/interactionparameters.h"
#include "Crypto/keyderivationparameters.h"
#include "Crypto/keypairgenerationparameters.h"
#include "Crypto/keypairgenerationparameters_p.h"

#include "Crypto/serialization_p.h"
#include "Crypto/key_p.h"

#include <QtDBus/QDBusArgument>

#include <QtCore/QString>
#include <QtCore/QLoggingCategory>
#include <QtCore/QBuffer>
#include <QtCore/QDataStream>
#include <QtCore/QByteArray>

Q_LOGGING_CATEGORY(lcSailfishCryptoSerialization, "org.sailfishos.crypto.serialization", QtWarningMsg)

namespace Sailfish {

namespace Crypto {

Key
Key::deserialize(const QByteArray &data, bool *ok)
{
    QBuffer buffer;
    buffer.setData(data);
    buffer.open(QIODevice::ReadOnly);

    QDataStream in(&buffer);

    quint32 magic;
    in >> magic;
    if (magic != 0x4B657900) {
        qCWarning(lcSailfishCryptoSerialization) << "Cannot deserialize key, bad magic number:" << magic;
        if (ok) {
            *ok = false;
        }
        return Key();
    }

    qint32 version;
    in >> version;
    if (version != 100) {
        qCWarning(lcSailfishCryptoSerialization) << "Cannot deserialize key, bad version number:" << version;
        if (ok) {
            *ok = false;
        }
        return Key();
    }

    in.setVersion(QDataStream::Qt_5_6);

    QString name, collectionName, storagePluginName;
    int iorigin = 0, ialgorithm = 0, ioperations = 0, icomponentConstraints = 0, isize = 0;
    QByteArray publicKey, privateKey, secretKey;
    QVector<QByteArray> customParameters;
    Key::FilterData filterData;

    in >> name;
    in >> collectionName;
    in >> storagePluginName;

    in >> iorigin;
    in >> ialgorithm;
    in >> ioperations;
    in >> icomponentConstraints;
    in >> isize;

    in >> publicKey;
    in >> privateKey;
    in >> secretKey;

    in >> customParameters;

    in >> filterData;

    buffer.close();

    Key retn;
    retn.setIdentifier(Key::Identifier(name, collectionName, storagePluginName));
    retn.setOrigin(static_cast<Key::Origin>(iorigin));
    retn.setAlgorithm(static_cast<CryptoManager::Algorithm>(ialgorithm));
    retn.setOperations(static_cast<CryptoManager::Operations>(ioperations));
    retn.setComponentConstraints(static_cast<Key::Components>(icomponentConstraints));
    retn.setSize(isize);
    retn.setPublicKey(publicKey);
    retn.setPrivateKey(privateKey);
    retn.setSecretKey(secretKey);
    retn.setCustomParameters(customParameters);
    retn.setFilterData(filterData);

    if (ok) {
        *ok = true;
    }
    return retn;
}

QByteArray
Key::serialize(const Key &key, Key::SerializationMode serializationMode)
{
    QByteArray byteArray;
    QBuffer buffer(&byteArray);
    buffer.open(QIODevice::WriteOnly);

    QDataStream out(&buffer);

    // Write a header with a "magic number" and a version
    out << (quint32)0x4B657900; // Key\0
    out << (qint32)100;         // version 1.0.0

    // Set the output format version
    out.setVersion(QDataStream::Qt_5_6);

    if (serializationMode == Key::LosslessSerializationMode) {
        out << key.identifier().name();
        out << key.identifier().collectionName();
        out << key.identifier().storagePluginName();
    } else {
        out << QString();
        out << QString();
        out << QString();
    }

    out << static_cast<int>(key.origin());
    out << static_cast<int>(key.algorithm());
    out << static_cast<int>(key.operations());
    out << static_cast<int>(key.componentConstraints());
    out << key.size();

    out << key.publicKey();
    out << key.privateKey();
    out << key.secretKey();

    out << key.customParameters();

    if (serializationMode == Key::LosslessSerializationMode) {
        out << key.filterData();
    } else {
        out << Key::FilterData();
    }

    buffer.close();

    return byteArray;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::Algorithm &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::Algorithm>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::Algorithm &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, Key::Origin &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<Key::Origin>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const Key::Origin &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::BlockMode &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::BlockMode>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::BlockMode &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::EncryptionPadding &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::EncryptionPadding>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::EncryptionPadding &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::SignaturePadding &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::SignaturePadding>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::SignaturePadding &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::DigestFunction &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::DigestFunction>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::DigestFunction &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::Operation &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::Operation>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::Operation &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::Operations &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::Operations>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::Operations &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::VerificationStatusType &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::VerificationStatusType>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::VerificationStatusType &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDataStream& operator>>(QDataStream& in, CryptoManager::VerificationStatus &v)
{
    quint32 temp = 0;
    in >> temp;
    v = static_cast<CryptoManager::VerificationStatus>(temp);
    return in;
}

QDataStream& operator<<(QDataStream& out, const CryptoManager::VerificationStatus &v)
{
    quint32 temp = static_cast<quint32>(v);
    out << temp;
    return out;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key &key)
{
    //((sss)iiiiiayayayaay(a{sv}))
    argument.beginStructure();
    argument << key.identifier();
    argument << static_cast<int>(key.origin());
    argument << static_cast<int>(key.algorithm());
    argument << static_cast<int>(key.operations());
    argument << static_cast<int>(key.componentConstraints());
    argument << key.size();
    argument << key.publicKey();
    argument << key.privateKey();
    argument << key.secretKey();
    argument << key.customParameters();
    argument << key.filterData();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key &key)
{
    Key::Identifier identifier;
    int origin = 0;
    int algorithm = 0;
    int operations = 0;
    int componentConstraints = 0;
    int size = 0;
    QByteArray publicKey;
    QByteArray privateKey;
    QByteArray secretKey;
    QVector<QByteArray> customParameters;
    Key::FilterData filterData;

    argument.beginStructure();
    argument >> identifier
             >> origin
             >> algorithm
             >> operations
             >> componentConstraints
             >> size
             >> publicKey
             >> privateKey
             >> secretKey
             >> customParameters
             >> filterData;
    argument.endStructure();

    key.setIdentifier(identifier);
    key.setOrigin(static_cast<Sailfish::Crypto::Key::Origin>(origin));
    key.setAlgorithm(static_cast<Sailfish::Crypto::CryptoManager::Algorithm>(algorithm));
    key.setOperations(static_cast<Sailfish::Crypto::CryptoManager::Operations>(operations));
    key.setComponentConstraints(static_cast<Sailfish::Crypto::Key::Components>(componentConstraints));
    key.setSize(size);
    key.setPublicKey(publicKey);
    key.setPrivateKey(privateKey);
    key.setSecretKey(secretKey);
    key.setCustomParameters(customParameters);
    key.setFilterData(filterData);

    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key::Identifier &identifier)
{
    argument.beginStructure();
    argument << identifier.name();
    argument << identifier.collectionName();
    argument << identifier.storagePluginName();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key::Identifier &identifier)
{
    QString name, collectionName, storagePluginName;
    argument.beginStructure();
    argument >> name;
    argument >> collectionName;
    argument >> storagePluginName;
    argument.endStructure();
    identifier = Key::Identifier(name, collectionName, storagePluginName);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key::FilterData &filterData)
{
    QVariantMap asv;
    for (QMap<QString,QString>::const_iterator it = filterData.constBegin(); it != filterData.constEnd(); ++it) {
        asv.insert(it.key(), it.value());
    }

    argument.beginStructure();
    argument << asv;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key::FilterData &filterData)
{
    QVariantMap asv;
    argument.beginStructure();
    argument >> asv;
    argument.endStructure();

    QMap<QString, QString> data;
    for (QVariantMap::const_iterator it = asv.constBegin(); it != asv.constEnd(); ++it) {
        data.insert(it.key(), it.value().toString());
    }

    filterData = data;
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key::Origin origin)
{
    argument.beginStructure();
    argument << static_cast<int>(origin);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key::Origin &origin)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    origin = static_cast<Key::Origin>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::Algorithm algorithm)
{
    argument.beginStructure();
    argument << static_cast<int>(algorithm);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::Algorithm &algorithm)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    algorithm = static_cast<CryptoManager::Algorithm>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::BlockMode mode)
{
    argument.beginStructure();
    argument << static_cast<int>(mode);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::BlockMode &mode)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    mode = static_cast<CryptoManager::BlockMode>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::EncryptionPadding padding)
{
    argument.beginStructure();
    argument << static_cast<int>(padding);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::EncryptionPadding &padding)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    padding = static_cast<CryptoManager::EncryptionPadding>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::SignaturePadding padding)
{
    argument.beginStructure();
    argument << static_cast<int>(padding);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::SignaturePadding &padding)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    padding = static_cast<CryptoManager::SignaturePadding>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::DigestFunction digest)
{
    argument.beginStructure();
    argument << static_cast<int>(digest);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::DigestFunction &digest)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    digest = static_cast<CryptoManager::DigestFunction>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::MessageAuthenticationCode mac)
{
    argument.beginStructure();
    argument << static_cast<int>(mac);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::MessageAuthenticationCode &mac)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    mac = static_cast<CryptoManager::MessageAuthenticationCode>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::KeyDerivationFunction kdf)
{
    argument.beginStructure();
    argument << static_cast<int>(kdf);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::KeyDerivationFunction &kdf)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    kdf = static_cast<CryptoManager::KeyDerivationFunction>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::Operation operation)
{
    argument.beginStructure();
    argument << static_cast<int>(operation);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::Operation &operation)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    operation = static_cast<CryptoManager::Operation>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::Operations operations)
{
    argument.beginStructure();
    argument << static_cast<int>(operations);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::Operations &operations)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    operations = static_cast<CryptoManager::Operations>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::VerificationStatus verificationStatus)
{
    argument.beginStructure();
    argument << static_cast<int>(verificationStatus);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::VerificationStatus &verificationStatus)
{
    int data = 0;
    argument.beginStructure();
    argument >> data;
    argument.endStructure();
    verificationStatus = static_cast<CryptoManager::VerificationStatus>(data);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CryptoManager::VerificationStatusType verificationStatusType)
{
    argument.beginStructure();
    argument << static_cast<int>(verificationStatusType);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CryptoManager::VerificationStatusType &verificationStatusType)
{
    int data = 0;
    argument.beginStructure();
    argument >> data;
    argument.endStructure();
    verificationStatusType = static_cast<CryptoManager::VerificationStatusType>(data);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key::Component component)
{
    argument.beginStructure();
    argument << static_cast<int>(component);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key::Component &component)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    component = static_cast<Key::Component>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Key::Components components)
{
    argument.beginStructure();
    argument << static_cast<int>(components);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Key::Components &components)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    components = static_cast<Key::Components>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Result &result)
{
    argument.beginStructure();
    argument << static_cast<int>(result.code()) << result.errorCode() << result.storageErrorCode() << result.errorMessage();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Result &result)
{
    int code = 0;
    int errorCode = 0;
    int storageErrorCode = 0;
    QString message;

    argument.beginStructure();
    argument >> code >> errorCode >> storageErrorCode >> message;
    argument.endStructure();

    result.setCode(static_cast<Result::ResultCode>(code));
    result.setErrorCode(static_cast<Result::ErrorCode>(errorCode));
    result.setStorageErrorCode(storageErrorCode);
    result.setErrorMessage(message);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const PluginInfo &info)
{
    argument.beginStructure();
    argument << info.displayName() << info.name() << info.version() << static_cast<int>(info.statusFlags());
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, PluginInfo &info)
{
    QString displayName;
    QString name;
    int version = 0;
    int iStatusFlags = 0;
    argument.beginStructure();
    argument >> displayName >> name >> version >> iStatusFlags;
    argument.endStructure();
    info = PluginInfo(displayName, name, version, static_cast<PluginInfo::StatusFlags>(iStatusFlags));
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const CipherRequest::CipherMode mode)
{
    argument.beginStructure();
    argument << static_cast<int>(mode);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, CipherRequest::CipherMode &mode)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    mode = static_cast<CipherRequest::CipherMode>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Crypto::InteractionParameters::InputType &type)
{
    int itype = static_cast<int>(type);
    argument.beginStructure();
    argument << itype;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Crypto::InteractionParameters::InputType &type)
{
    int itype = 0;
    argument.beginStructure();
    argument >> itype;
    argument.endStructure();
    type = static_cast<InteractionParameters::InputType>(itype);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Crypto::InteractionParameters::EchoMode &mode)
{
    int imode = static_cast<int>(mode);
    argument.beginStructure();
    argument << imode;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Crypto::InteractionParameters::EchoMode &mode)
{
    int imode = 0;
    argument.beginStructure();
    argument >> imode;
    argument.endStructure();
    mode = static_cast<InteractionParameters::EchoMode>(imode);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Crypto::InteractionParameters::Operation &op)
{
    int iop = static_cast<int>(op);
    argument.beginStructure();
    argument << iop;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Crypto::InteractionParameters::Operation &op)
{
    int iop = 0;
    argument.beginStructure();
    argument >> iop;
    argument.endStructure();
    op = static_cast<InteractionParameters::Operation>(iop);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Crypto::InteractionParameters::PromptText &promptText)
{
    argument.beginMap(QVariant::Int, QVariant::String);
    for (auto it = promptText.begin(); it != promptText.end(); ++it) {
        argument.beginMapEntry();
        argument << static_cast<int>(it.key()) << it.value();
        argument.endMapEntry();
    }
    argument.endMapEntry();

    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Crypto::InteractionParameters::PromptText &promptText)
{
    int key;
    QString value;

    argument.beginMap();
    while (!argument.atEnd()) {
        argument.beginMapEntry();
        argument >> key >> value;
        argument.endMapEntry();

        promptText.insert(static_cast<Sailfish::Crypto::InteractionParameters::Prompt>(key), value);
    }
    argument.endMapEntry();

    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const InteractionParameters &request)
{
    argument.beginStructure();
    argument << request.keyName()
             << request.collectionName()
             << request.pluginName()
             << request.applicationId()
             << request.operation()
             << request.authenticationPluginName()
             << request.promptText()
             << request.inputType()
             << request.echoMode();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, InteractionParameters &request)
{
    QString keyName;
    QString collectionName;
    QString pluginName;
    QString applicationId;
    InteractionParameters::Operation operation = InteractionParameters::UnknownOperation;
    QString authenticationPluginName;
    InteractionParameters::PromptText promptText;
    InteractionParameters::InputType inputType = InteractionParameters::UnknownInput;
    InteractionParameters::EchoMode echoMode = InteractionParameters::PasswordEcho;

    argument.beginStructure();
    argument >> keyName
             >> collectionName
             >> pluginName
             >> applicationId
             >> operation
             >> authenticationPluginName
             >> promptText
             >> inputType
             >> echoMode;
    argument.endStructure();

    request.setKeyName(keyName);
    request.setCollectionName(collectionName);
    request.setPluginName(pluginName);
    request.setApplicationId(applicationId);
    request.setOperation(operation);
    request.setAuthenticationPluginName(authenticationPluginName);
    request.setPromptText(promptText);
    request.setInputType(inputType);
    request.setEchoMode(echoMode);

    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const KeyDerivationParameters &skdfParams)
{
    argument.beginStructure();
    argument << skdfParams.inputData()
             << skdfParams.salt()
             << skdfParams.keyDerivationFunction()
             << skdfParams.keyDerivationMac()
             << skdfParams.keyDerivationAlgorithm()
             << skdfParams.keyDerivationDigestFunction()
             << skdfParams.memorySize()
             << skdfParams.iterations()
             << skdfParams.parallelism()
             << skdfParams.outputKeySize()
             << skdfParams.customParameters();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, KeyDerivationParameters &skdfParams)
{
    QByteArray inputData;
    QByteArray salt;
    CryptoManager::KeyDerivationFunction keyDerivationFunction = CryptoManager::KdfUnknown;
    CryptoManager::MessageAuthenticationCode keyDerivationMac = CryptoManager::MacUnknown;
    CryptoManager::Algorithm keyDerivationAlgorithm = CryptoManager::AlgorithmUnknown;
    CryptoManager::DigestFunction keyDerivationDigestFunction = CryptoManager::DigestUnknown;
    qint64 memorySize = 0;
    int iterations = 0;
    int parallelism = 0;
    int outputKeySize = 0;
    QVariantMap customParameters;

    argument.beginStructure();
    argument >> inputData
             >> salt
             >> keyDerivationFunction
             >> keyDerivationMac
             >> keyDerivationAlgorithm
             >> keyDerivationDigestFunction
             >> memorySize
             >> iterations
             >> parallelism
             >> outputKeySize
             >> customParameters;
    argument.endStructure();

    skdfParams.setInputData(inputData);
    skdfParams.setSalt(salt);
    skdfParams.setKeyDerivationFunction(keyDerivationFunction);
    skdfParams.setKeyDerivationMac(keyDerivationMac);
    skdfParams.setKeyDerivationAlgorithm(keyDerivationAlgorithm);
    skdfParams.setKeyDerivationDigestFunction(keyDerivationDigestFunction);
    skdfParams.setMemorySize(memorySize);
    skdfParams.setIterations(iterations);
    skdfParams.setParallelism(parallelism);
    skdfParams.setOutputKeySize(outputKeySize);
    skdfParams.setCustomParameters(customParameters);

    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const KeyPairGenerationParameters::KeyPairType type)
{
    argument.beginStructure();
    argument << static_cast<int>(type);
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, KeyPairGenerationParameters::KeyPairType &type)
{
    int iv = 0;
    argument.beginStructure();
    argument >> iv;
    argument.endStructure();
    type = static_cast<KeyPairGenerationParameters::KeyPairType>(iv);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const KeyPairGenerationParameters &kpgParams)
{
    argument.beginStructure();
    argument << static_cast<int>(kpgParams.keyPairType())
             << KeyPairGenerationParametersPrivate::subclassParameters(kpgParams)
             << kpgParams.customParameters();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, KeyPairGenerationParameters &kpgParams)
{
    int ikeyPairType;
    QVariantMap subclassParameters;
    QVariantMap customParameters;

    argument.beginStructure();
    argument >> ikeyPairType
             >> subclassParameters
             >> customParameters;
    argument.endStructure();

    kpgParams.setKeyPairType(static_cast<KeyPairGenerationParameters::KeyPairType>(ikeyPairType));
    KeyPairGenerationParametersPrivate::setSubclassParameters(kpgParams, subclassParameters);
    kpgParams.setCustomParameters(customParameters);

    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const LockCodeRequest::LockCodeTargetType &type)
{
    int itype = static_cast<int>(type);
    argument.beginStructure();
    argument << itype;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, LockCodeRequest::LockCodeTargetType &type)
{
    int itype = 0;
    argument.beginStructure();
    argument >> itype;
    argument.endStructure();
    type = static_cast<LockCodeRequest::LockCodeTargetType>(itype);
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const LockCodeRequest::LockStatus &status)
{
    int istatus = static_cast<int>(status);
    argument.beginStructure();
    argument << istatus;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, LockCodeRequest::LockStatus &status)
{
    int istatus = 0;
    argument.beginStructure();
    argument >> istatus;
    argument.endStructure();
    status = static_cast<LockCodeRequest::LockStatus>(istatus);
    return argument;
}

} // namespace Crypto

} // namespace Sailfish
