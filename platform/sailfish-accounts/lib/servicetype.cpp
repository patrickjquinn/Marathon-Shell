// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "servicetype.h"
#include "globaltranslatorcache_p.h"
#include <QTranslator>

/*!
    \qmltype ServiceType
    \instantiates ServiceType
    \inqmlmodule Sailfish.Accounts 1
    \brief Reports information about a particular service type

    This type provides information about a particular service type
    of a service provided by a provider.  For example, "IM" type
    services provide instant messaging capabilities.
*/

ServiceType::ServiceType(const Accounts::ServiceType &serviceType, QObject *parent)
    : QObject(parent), m_serviceType(serviceType)
{
}

ServiceType::~ServiceType()
{
}

/*!
    \qmlproperty string ServiceType::name
    This property holds the name of the service type
*/

QString ServiceType::name() const
{
    return m_serviceType.name();
}

/*!
    \qmlproperty string ServiceType::displayName
    This property holds the display name of the service type.
    This display name can be displayed in lists or
    dialogues in the UI of applications.
*/

QString ServiceType::displayName() const
{
    return SailfishAccounts::translatedDisplayName(m_serviceType);
}

/*!
    \qmlproperty string ServiceType::iconName
    This property holds the name of the icon associated with the service type, if it exists
*/

QString ServiceType::iconName() const
{
    return m_serviceType.iconName();
}

/*!
    \qmlproperty list ServiceType::tags
    This property holds the tags which have been associated with the service type.
*/

QStringList ServiceType::tags() const
{
    return m_serviceType.tags().values(); // Modified by Shipwright for Qt 6: QSet::values()
}
