// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/plugininfo.h"
#include "Crypto/plugininfo_p.h"

using namespace Sailfish::Crypto;

//--------------------------------------------

PluginInfoPrivate::PluginInfoPrivate()
    : QSharedData()
    , m_version(0)
    , m_statusFlags(PluginInfo::Unknown)
{
}

PluginInfoPrivate::PluginInfoPrivate(const PluginInfoPrivate &other)
    : QSharedData(other)
    , m_name(other.m_name)
    , m_version(other.m_version)
    , m_statusFlags(other.m_statusFlags)
{
}

PluginInfoPrivate::~PluginInfoPrivate()
{
}

//--------------------------------------------

/*!
  \class PluginInfo
  \brief Information about a plugin
  \inmodule SailfishCrypto
  \inheaderfile Crypto/plugininfo.h

  The result encapsulates the name and version of a plugin.
  Instances of this object which contain information about
  plugins which are available for use by clients can be
  accessed via PluginInfoRequest.

  Clients should target a specific plugin when they implement
  their application, as each plugin may have slightly different
  semantics.

  Clients must read the documentation supplied by the plugin
  implementor in order to know what functionality a given version
  of the plugin supports.
 */

/*!
  \brief Constructs a plugin info object containing the given \a name, \a version and \a status
 */
PluginInfo::PluginInfo(const QString &displayName,
                       const QString &name,
                       int version,
                       StatusFlags status)
    : d_ptr(new PluginInfoPrivate)
{
    d_ptr->m_displayName = displayName;
    d_ptr->m_name = name;
    d_ptr->m_version = version;
    d_ptr->m_statusFlags = status;
}

/*!
  \brief Constructs a copy of the \a other plugin info object
 */
PluginInfo::PluginInfo(const PluginInfo &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the plugin info object
 */
PluginInfo::~PluginInfo()
{
}

/*!
  \brief Assigns the \a other plugin info object to this plugin info object
 */
PluginInfo& PluginInfo::operator=(const PluginInfo &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns the display name of the plugin

  This is the user-friendly, human-readable name reported by the
  plugin and should already be translated.
 */
QString PluginInfo::displayName() const
{
    return d_ptr->m_displayName;
}

/*!
  \brief Returns the name of the plugin

  This is a unique identifier for the plugin, and is not
  necessarily human-readable.
 */
QString PluginInfo::name() const
{
    return d_ptr->m_name;
}

/*!
  \brief Returns the version of the plugin
 */
int PluginInfo::version() const
{
    return d_ptr->m_version;
}

/*!
  \brief Returns the status flags of the plugin
 */
PluginInfo::StatusFlags PluginInfo::statusFlags() const
{
    return d_ptr->m_statusFlags;
}

/*!
  \brief Returns true if the \a lhs plugin info object is equal to the \a rhs plugin info object
 */
bool Sailfish::Crypto::operator==(const PluginInfo &lhs, const PluginInfo &rhs)
{
    return lhs.displayName() == rhs.displayName()
            && lhs.name() == rhs.name()
            && lhs.version() == rhs.version()
            && lhs.statusFlags() == rhs.statusFlags();
}

/*!
  \brief Returns false if the \a lhs plugin info object is equal to the \a rhs plugin info object
 */
bool Sailfish::Crypto::operator!=(const PluginInfo &lhs, const PluginInfo &rhs)
{
    return !(operator==(lhs, rhs));
}

/*!
  \brief Returns true if the \a lhs plugin info object should sort less than \a rhs plugin info object
 */
bool Sailfish::Crypto::operator<(const PluginInfo &lhs, const PluginInfo &rhs)
{
    if (lhs.name() != rhs.name())
        return lhs.name() < rhs.name();
    if (lhs.version() != rhs.version())
        return lhs.version() < rhs.version();
    if (lhs.displayName() != rhs.displayName())
        return lhs.displayName() < rhs.displayName();
    return lhs.statusFlags() < rhs.statusFlags();
}
