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

#include "service-type.h"

#undef signals
#include <libaccounts-glib.h>

using namespace Accounts;

namespace Accounts {
/*!
 * @class ServiceType
 * @headerfile service-type.h Accounts/ServiceType
 *
 * @brief Representation of an account service type.
 *
 * @details The ServiceType object represents an account service type. It can
 * be used to retrieve some basic properties of the service type (such as
 * name and icon) and to get access to the contents of the XML file which
 * defines it.
 */
}; // namespace

ServiceType::ServiceType(AgServiceType *serviceType, ReferenceMode mode):
    m_serviceType(serviceType),
    m_tags(nullptr)
{
    if (m_serviceType != nullptr && mode == AddReference)
        ag_service_type_ref(m_serviceType);
}

/*!
 * Construct an invalid serviceType.
 */
ServiceType::ServiceType():
    m_serviceType(nullptr),
    m_tags(nullptr)
{
}

/*!
 * Copy constructor. Copying a ServiceType object is very cheap, because the
 * data is shared among copies.
 */
ServiceType::ServiceType(const ServiceType &other):
    m_serviceType(other.m_serviceType),
    m_tags(nullptr)
{
    if (m_serviceType != nullptr)
        ag_service_type_ref(m_serviceType);
}

ServiceType &ServiceType::operator=(const ServiceType &other)
{
    if (m_serviceType == other.m_serviceType) return *this;
    if (m_serviceType != nullptr)
        ag_service_type_unref(m_serviceType);
    m_serviceType = other.m_serviceType;
    if (m_serviceType != nullptr)
        ag_service_type_ref(m_serviceType);
    return *this;
}

ServiceType::~ServiceType()
{
    if (m_serviceType != nullptr) {
        ag_service_type_unref(m_serviceType);
        m_serviceType = nullptr;
    }
    if (m_tags != nullptr) {
        delete m_tags;
        m_tags = nullptr;
    }
}

/*!
 * Check whether this object represents a ServiceType.
 * @return true if the ServiceType is a valid one.
 */
bool ServiceType::isValid() const
{
    return m_serviceType != nullptr;
}

/*!
 * Returns the name (ID) of the service type.
 */
QString ServiceType::name() const
{
    if (Q_UNLIKELY(!isValid())) return QString();
    return UTF8(ag_service_type_get_name(m_serviceType));
}

/*!
 * @return The description of the service type.
 */
QString ServiceType::description() const
{
    return UTF8(ag_service_type_get_description(m_serviceType));
}

/*!
 * @return The display name of the service type; this is a string that
 * could be shown in the UI to describe the service type to the user.
 *
 * The library attempts to translate this string by passing it to the
 * qtTrId() function; in order for this to work you must make sure that
 * the translation catalogue has been loaded before, if needed.
 */
QString ServiceType::displayName() const
{
    const gchar *id;

    /* libaccounts-glib returns the display name untranslated. */
    id = ag_service_type_get_display_name(m_serviceType);
    if (id != NULL) {
        return qtTrId(id);
    } else {
        return QString();
    }
}

/*!
 * @return The name of the translation catalog, which can be used to
 * translate the displayName()
 */
QString ServiceType::trCatalog() const
{
    return ASCII(ag_service_type_get_i18n_domain(m_serviceType));
}

/*!
 * @return The icon name
 */
QString ServiceType::iconName() const
{
    return ASCII(ag_service_type_get_icon_name(m_serviceType));
}

/*!
 * Check if this service type has a tag.
 *
 * @param tag Tag to look for
 *
 * @return Service type has the tag?
 */
bool ServiceType::hasTag(const QString &tag) const
{
    return ag_service_type_has_tag(m_serviceType, tag.toUtf8().constData());
}

/*!
 * Return all tags of the service type as a set.
 *
 * @return Set of tags
 */
QSet<QString> ServiceType::tags() const
{
    if (m_tags)
        return *m_tags;

    m_tags = new QSet<QString>;
    GList *list = ag_service_type_get_tags(m_serviceType);
    GList *iter = list;
    while (iter != NULL) {
        m_tags->insert(UTF8(reinterpret_cast<const gchar *> (iter->data)));
        iter = g_list_next(iter);
    }
    g_list_free(list);
    return *m_tags;
}

/*!
 * @return The DOM of the whole XML service file
 */
const QDomDocument ServiceType::domDocument() const
{
    const gchar *data;
    gsize len;

    ag_service_type_get_file_contents(m_serviceType, &data, &len);

    QDomDocument doc;
    QString errorStr;
    int errorLine;
    int errorColumn;
    // Qt 6.8 deprecates the out-parameter setContent(); ParseResult is 6.5+.
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    const QDomDocument::ParseResult parsed =
        doc.setContent(QByteArray(data, len), QDomDocument::ParseOption::UseNamespaceProcessing);
    if (!parsed) {
        errorStr = parsed.errorMessage;
        errorLine = static_cast<int>(parsed.errorLine);
        errorColumn = static_cast<int>(parsed.errorColumn);
#else
    if (!doc.setContent(QByteArray(data, len), true,
                        &errorStr, &errorLine, &errorColumn)) {
#endif
        QString message(QStringLiteral("Parse error reading serviceType file "
                              "at line %1, column %2:\n%3"));
        message = message.arg(errorLine).arg(errorColumn).arg(errorStr);
        qWarning() << __PRETTY_FUNCTION__ << message;
    }

    return doc;
}

