// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SERIALIZATION_H
#define LIBSAILFISHSECRETS_SERIALIZATION_H

// WARNING!
//
// This is private API, used for internal implementation only!
// No BC/SC guarantees are made for the methods in this file!

#include "Secrets/secretsglobal.h"
#include "Secrets/result.h"
#include "Secrets/secret.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/plugininfo.h"
#include "Secrets/healthcheckrequest.h"
#include "Secrets/secretmanager.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/interactionresponse.h"
#include "Secrets/lockcoderequest.h"

#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusMetaType>

namespace Sailfish {

namespace Secrets {


QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::Result &result) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::Result &result) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::Secret &secret) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::Secret &secret) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::Secret::Identifier &identifier) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::Secret::Identifier &identifier) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::SecretManager::UserInteractionMode mode) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::SecretManager::UserInteractionMode &mode) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::SecretManager::AccessControlMode mode) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::SecretManager::AccessControlMode &mode) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic semantic) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic &semantic) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic semantic) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic &semantic) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::SecretManager::FilterOperator filterOperator) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::SecretManager::FilterOperator &filterOperator) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::PluginInfo &info) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::PluginInfo &info) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionParameters::InputType &type) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionParameters::InputType &type) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionParameters::EchoMode &mode) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionParameters::EchoMode &mode) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionParameters::Operation &op) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionParameters::Operation &op) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionParameters::PromptText &prompt) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionParameters::PromptText &prompt) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionParameters &request) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionParameters &request) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::InteractionResponse &response) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::InteractionResponse &response) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::LockCodeRequest::LockCodeTargetType &type) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::LockCodeRequest::LockCodeTargetType &type) SAILFISH_SECRETS_API;
QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::LockCodeRequest::LockStatus &status) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::LockCodeRequest::LockStatus &status) SAILFISH_SECRETS_API;

QDBusArgument &operator<<(QDBusArgument &argument, const Sailfish::Secrets::HealthCheckRequest::Health &h) SAILFISH_SECRETS_API;
const QDBusArgument &operator>>(const QDBusArgument &argument, Sailfish::Secrets::HealthCheckRequest::Health &h) SAILFISH_SECRETS_API;

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_SERIALIZATION_H
