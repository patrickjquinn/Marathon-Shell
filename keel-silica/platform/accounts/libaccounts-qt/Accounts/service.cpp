// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2012 Intel Corporation.
// SPDX-License-Identifier: LGPL-2.1-only
// Modified by Shipwright for Qt 6: QDomDocument::setContent() with out-parameters is deprecated (6.8); ParseResult on 6.5+.
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2011 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 * Copyright (C) 2012 Intel Corporation.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
 * Contact: Jussi Laako <jussi.laako@linux.intel.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */

#include "service.h"

#undef signals
#include <libaccounts-glib.h>

using namespace Accounts;

namespace Accounts {
/*!
 * @class Service
 * @headerfile service.h Accounts/Service
 *
 * @brief Representation of an account service.
 *
 * @details The Service object represents an account service. It can be used to
 * retrieve some basic properties of the service (such as name, type and
 * provider) and to get access to the contents of the XML file which defines
 * it.
 */
}; // namespace

Service::Service(AgService *service, ReferenceMode mode):
    m_service(service),
    m_tags(nullptr)
{
    if (m_service != nullptr && mode == AddReference)
        ag_service_ref(m_service);
}

/*!
 * Construct an invalid service.
 */
Service::Service():
    m_service(nullptr),
    m_tags(nullptr)
{
}

/*!
 * Copy constructor. Copying a Service object is very cheap, because the
 * data is shared among copies.
 */
Service::Service(const Service &other):
    m_service(other.m_service),
    m_tags(nullptr)
{
    if (m_service != nullptr)
        ag_service_ref(m_service);
}

Service &Service::operator=(const Service &other)
{
    if (m_service == other.m_service) return *this;
    if (m_service != nullptr)
        ag_service_unref(m_service);
    m_service = other.m_service;
    if (m_service != nullptr)
        ag_service_ref(m_service);
    return *this;
}

Service::~Service()
{
    if (m_service != nullptr) {
        ag_service_unref(m_service);
        m_service = nullptr;
    }
    if (m_tags != nullptr) {
        delete m_tags;
        m_tags = nullptr;
    }
}

/*!
 * Check whether this object represents a Service.
 * @return true if the Service is a valid one.
 */
bool Service::isValid() const
{
    return m_service != nullptr;
}

/*!
 * Get the name of the service. This can be used as a unique identifier for
 * this service.
 * @return The unique name of the service.
 */
QString Service::name() const
{
    if (Q_UNLIKELY(!isValid())) return QString();
    return UTF8(ag_service_get_name(m_service));
}

/*!
 * Get the description of the service.
 * @return The description of the service.
 */
QString Service::description() const
{
    return UTF8(ag_service_get_description(m_service));
}

/*!
 * Get the display name of the service, untranslated.
 * @return The display name of the service.
 */
QString Service::displayName() const
{
    return UTF8(ag_service_get_display_name(m_service));
}

/*!
 * Get the service type ID of the service.
 * @return The service type of the service.
 */
QString Service::serviceType() const
{
    return ASCII(ag_service_get_service_type(m_service));
}

/*!
 * @return The translation catalog of the service.
 */
QString Service::trCatalog() const
{
    return ASCII(ag_service_get_i18n_domain(m_service));
}

/*!
 * Get the provider ID of the service.
 * @return The provider of the service.
 */
QString Service::provider() const
{
    return UTF8(ag_service_get_provider(m_service));
}

/*!
 * Get the icon name for this service.
 * @return The icon name.
 */
QString Service::iconName() const
{
    return ASCII(ag_service_get_icon_name(m_service));
}

/*!
 * Check if this service has a tag.
 *
 * @param tag Tag to look for
 *
 * @return Service has the tag?
 */
bool Service::hasTag(const QString &tag) const
{
    return ag_service_has_tag(m_service, tag.toUtf8().constData());
}

/*!
 * Return all tags of the service as a set.
 *
 * @return Set of tags
 */
QSet<QString> Service::tags() const
{
    if (m_tags)
        return *m_tags;

    m_tags = new QSet<QString>;
    GList *list = ag_service_get_tags(m_service);
    GList *iter = list;
    while (iter != NULL) {
        m_tags->insert(UTF8(reinterpret_cast<const gchar *> (iter->data)));
        iter = g_list_next(iter);
    }
    g_list_free(list);
    return *m_tags;
}

/*!
 * Get the contents of the service XML file.
 * @return The DOM of the whole XML service file
 */
const QDomDocument Service::domDocument() const
{
    const gchar *data;

    ag_service_get_file_contents(m_service, &data, NULL);

    QDomDocument doc;
    QString errorStr;
    int errorLine;
    int errorColumn;
    // Qt 6.8 deprecates the out-parameter setContent(); ParseResult is 6.5+.
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    const QDomDocument::ParseResult parsed =
        doc.setContent(QByteArray(data), QDomDocument::ParseOption::UseNamespaceProcessing);
    if (!parsed)
    {
        errorStr = parsed.errorMessage;
        errorLine = static_cast<int>(parsed.errorLine);
        errorColumn = static_cast<int>(parsed.errorColumn);
#else
    if (!doc.setContent(QByteArray(data), true,
                        &errorStr, &errorLine, &errorColumn))
    {
#endif
        QString message(QStringLiteral("Parse error reading account service file "
                              "at line %1, column %2:\n%3"));
        message = message.arg(errorLine).arg(errorColumn).arg(errorStr);
        qWarning() << __PRETTY_FUNCTION__ << message;
    }
    return doc;
}

AgService *Service::service() const
{
    return m_service;
}

