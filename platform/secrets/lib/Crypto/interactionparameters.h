// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_INTERACTIONREQUEST_H
#define LIBSAILFISHCRYPTO_INTERACTIONREQUEST_H

#include "Crypto/cryptoglobal.h"

#include <QtCore/QString>
#include <QtCore/QSharedDataPointer>
#include <QtCore/QMap>
#include <QtCore/QMetaType>

namespace Sailfish {

namespace Crypto {

class InteractionParametersPrivate;
class SAILFISH_CRYPTO_API InteractionParameters {
    Q_GADGET
    Q_PROPERTY(QString keyName READ keyName WRITE setKeyName)
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName)
    Q_PROPERTY(QString pluginName READ pluginName WRITE setPluginName)
    Q_PROPERTY(QString applicationId READ applicationId WRITE setApplicationId)
    Q_PROPERTY(Operation operation READ operation WRITE setOperation)
    Q_PROPERTY(QString authenticationPluginName READ authenticationPluginName WRITE setAuthenticationPluginName)
    Q_PROPERTY(Sailfish::Crypto::InteractionParameters::PromptText promptText READ promptText WRITE setPromptText)
    Q_PROPERTY(InputType inputType READ inputType WRITE setInputType)
    Q_PROPERTY(EchoMode echoMode READ echoMode WRITE setEchoMode)

public:
    enum InputType {
        UnknownInput        = 0,
        AuthenticationInput = 1,  // returns non-empty data if the user authenticates via system dialog
        ConfirmationInput   = 2,  // returns non-empty data if the user allows the operation
        NumericInput        = 4,  // returns the numeric (e.g. PIN) data from the user
        AlphaNumericInput   = 8,  // returns the alphanumeric (e.g. passphrase) data from the user
        FingerprintInput    = 16, // returns the fingerprint data from the user
        IrisInput           = 32, // returns the iris data from the user
        RetinaInput         = 64, // returns the retina data from the user
        // reserved
        LastInputType       = 65536
    };
    Q_ENUM(InputType)
    Q_DECLARE_FLAGS(InputTypes, InputType)

    enum EchoMode {
        UnknownEcho = 0,
        NormalEcho,
        PasswordEcho,
        NoEcho,
        // reserved
        LastEchoMode = 63
    };
    Q_ENUM(EchoMode)

    enum Operation {
        UnknownOperation    = 0,

        RequestUserData     = 1 << 0,   // usually used in conjunction with StoreSecret, i.e. store data requested from user.

        UnlockDatabase      = 1 << 1,
        LockDatabase        = 1 << 2,
        ModifyLockDatabase  = 1 << 3,

        UnlockPlugin        = 1 << 4,
        LockPlugin          = 1 << 5,
        ModifyLockPlugin    = 1 << 6,

        CreateCollection    = 1 << 7,
        UnlockCollection    = 1 << 8,
        LockCollection      = 1 << 9,
        ModifyLockCollection= 1 << 10,
        DeleteCollection    = 1 << 11,

        ReadSecret          = 1 << 12,
        StoreSecret         = 1 << 13,
        UnlockSecret        = 1 << 14,
        LockSecret          = 1 << 15,
        ModifyLockSecret    = 1 << 16,
        DeleteSecret        = 1 << 17,

        Encrypt             = 1 << 18,
        Decrypt             = 1 << 19,
        Sign                = 1 << 20,
        Verify              = 1 << 21,
        DeriveDigest        = 1 << 22,
        DeriveMac           = 1 << 23,
        DeriveKey           = 1 << 24,
        StoreKey            = 1 << 25,
        ImportKey           = 1 << 26,

        // reserved
        LastOperation       = 1 << 30
    };
    Q_ENUM(Operation)
    Q_DECLARE_FLAGS(Operations, Operation)

    enum Prompt {
        Message,
        Instruction                 = 0x10,
        NewInstruction,
        RepeatInstruction,
        Accept                      = 0x20,
        Cancel                      = 0x30,
    };
    Q_ENUM(Prompt)

    class PromptText;
    InteractionParameters();
    InteractionParameters(const InteractionParameters &other);
    ~InteractionParameters();
    InteractionParameters& operator=(const InteractionParameters &other);

    bool isValid() const;

    QString keyName() const;
    void setKeyName(const QString &name);

    QString collectionName() const;
    void setCollectionName(const QString &name);

    QString pluginName() const;
    void setPluginName(const QString &name);

    QString applicationId() const;
    void setApplicationId(const QString &id);

    Operation operation() const;
    void setOperation(Operation op);

    // TODO: do we need an "operationArgument" parameter?
    // e.g. a filename which the client application wishes to perform the operation on?

    QString authenticationPluginName() const;
    void setAuthenticationPluginName(const QString &pluginName);

    PromptText promptText() const;
    void setPromptText(const PromptText &prompt);
    void setPromptText(const QString &message);

    InputType inputType() const;
    void setInputType(InputType type);

    EchoMode echoMode() const;
    void setEchoMode(EchoMode mode);

private:
    QSharedDataPointer<InteractionParametersPrivate> d_ptr;
    friend class InteractionParametersPrivate;
};

class SAILFISH_CRYPTO_API InteractionParameters::PromptText : private QMap<InteractionParameters::Prompt, QString>
{
    Q_GADGET
    Q_PROPERTY(QString message READ message WRITE setMessage)
    Q_PROPERTY(QString instruction READ instruction WRITE setInstruction)
    Q_PROPERTY(QString newInstruction READ newInstruction WRITE setNewInstruction)
    Q_PROPERTY(QString repeatInstruction READ repeatInstruction WRITE setRepeatInstruction)
    Q_PROPERTY(QString accept READ accept WRITE setAccept)
    Q_PROPERTY(QString cancel READ cancel WRITE setCancel)
public:
    PromptText() = default;
    PromptText(const PromptText &) = default;
    PromptText(std::initializer_list<std::pair<InteractionParameters::Prompt, QString> > list) : QMap(list) {}
    ~PromptText() = default;

    QString message() const { return value(Message); }
    void setMessage(const QString &message) { set(Message, message); }

    QString instruction() const { return value(Instruction); }
    void setInstruction(const QString &instruction) { return set(Instruction, instruction); }

    QString newInstruction() const { return value(NewInstruction); }
    void setNewInstruction(const QString &instruction) { set(NewInstruction, instruction); }

    QString repeatInstruction() const { return value(RepeatInstruction); }
    void setRepeatInstruction(const QString &instruction) { set(RepeatInstruction, instruction); }

    QString accept() const { return value(Accept); }
    void setAccept(const QString &label) { set(Accept, label); }

    QString cancel() const { return value(Cancel); }
    void setCancel(const QString &label) { set(Cancel, label); }

    PromptText &operator =(const PromptText &promptText) { QMap::operator =(promptText); return *this; }
    // Modified by Shipwright for Qt 6: QMap's comparison operators are free functions.
    bool operator == (const PromptText &promptText) const { return static_cast<const QMap &>(*this) == static_cast<const QMap &>(promptText); }
    bool operator != (const PromptText &promptText) const { return !(*this == promptText); }

    using QMap::operator [];

    using QMap::insert;
    using QMap::contains;
    using QMap::keys;
    using QMap::values;
    using QMap::begin;
    using QMap::end;
    using QMap::constBegin;
    using QMap::constEnd;

private:
    void set(InteractionParameters::Prompt prompt, const QString &text) {
        if (text.isEmpty()) { remove(prompt); } else { insert(prompt, text); } }
};

bool operator==(const Sailfish::Crypto::InteractionParameters &lhs, const Sailfish::Crypto::InteractionParameters &rhs) SAILFISH_CRYPTO_API;
bool operator!=(const Sailfish::Crypto::InteractionParameters &lhs, const Sailfish::Crypto::InteractionParameters &rhs) SAILFISH_CRYPTO_API;
bool operator<(const Sailfish::Crypto::InteractionParameters &lhs, const Sailfish::Crypto::InteractionParameters &rhs) SAILFISH_CRYPTO_API;
bool operator<(const Sailfish::Crypto::InteractionParameters::PromptText &lhs, const Sailfish::Crypto::InteractionParameters::PromptText &rhs) SAILFISH_CRYPTO_API;

} // Crypto

} // Sailfish

Q_DECLARE_OPERATORS_FOR_FLAGS(Sailfish::Crypto::InteractionParameters::InputTypes);
Q_DECLARE_OPERATORS_FOR_FLAGS(Sailfish::Crypto::InteractionParameters::Operations);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters::InputType);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters::EchoMode);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters::Operation);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters::Prompt);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters::PromptText);
Q_DECLARE_METATYPE(Sailfish::Crypto::InteractionParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::InteractionParameters, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHCRYPTO_INTERACTIONREQUEST_H
