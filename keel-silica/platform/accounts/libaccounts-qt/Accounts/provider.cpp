// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
// Modified by Shipwright for Qt 6: QDomDocument::setContent() with out-parameters is deprecated (6.8); ParseResult on 6.5+.
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2011 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
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

#include "provider.h"

#undef signals
#include <libaccounts-glib.h>


using namespace Accounts;

namespace Accounts {
/*!
 * @class Provider
 * @headerfile provider.h Accounts/Provider
 *
 * @brief Representation of an account provider.
 *
 * @details The Provider object represents an account provider. It can be used
 * to retrieve some basic properties of the provider (such as the name) and to
 * get access to the contents of the XML file which defines it.
 */
}; // namespace

Provider::Provider(AgProvider *provider, ReferenceMode mode):
    m_provider(provider),
    m_tags(nullptr)
{
    if (m_provider != nullptr && mode == AddReference)
        ag_provider_ref(m_provider);
}

/*!
 * Construct an invalid provider.
 */
Provider::Provider():
    m_provider(nullptr),
    m_tags(nullptr)
{
}

/*!
 * Copy constructor. Copying a Provider object is very cheap, because the
 * data is shared among copies.
 */
Provider::Provider(const Provider &other):
    m_provider(other.m_provider),
    m_tags(nullptr)
{
    if (m_provider != nullptr)
        ag_provider_ref(m_provider);
}

Provider &Provider::operator=(const Provider &other)
{
    if (m_provider == other.m_provider) return *this;
    if (m_provider != nullptr)
        ag_provider_unref(m_provider);
    m_provider = other.m_provider;
    if (m_provider != nullptr)
        ag_provider_ref(m_provider);
    return *this;
}

Provider::~Provider()
{
    if (m_provider != nullptr) {
        ag_provider_unref(m_provider);
        m_provider = nullptr;
    }
    if (m_tags != nullptr) {
        delete m_tags;
        m_tags = nullptr;
    }
}

/*!
 * Check whether this object represents a Provider.
 * @return true if the Provider is a valid one.
 */
bool Provider::isValid() const
{
    return m_provider != nullptr;
}

/*!
 * Get the name of the provider. This can be used as a unique identifier for
 * this provider.
 * @return The unique name of the provider.
 */
QString Provider::name() const
{
    if (Q_UNLIKELY(!isValid())) return QString();
    return UTF8(ag_provider_get_name(m_provider));
}

/*!
 * Get the display name of the provider, untranslated.
 * @return The display name of the provider.
 */
QString Provider::displayName() const
{
    return UTF8(ag_provider_get_display_name(m_provider));
}

/*!
 * Get the description of the provider, untranslated.
 * @return The description of the provider.
 */
QString Provider::description() const
{
    return UTF8(ag_provider_get_description(m_provider));
}

/*!
 * Get the name of the account plugin associated with the provider.
 * Some platforms might find it useful to store plugin names in the provider
 * XML files, especially when the same plugin can work for different providers.
 * @return The plugin name.
 */
QString Provider::pluginName() const
{
    return UTF8(ag_provider_get_plugin_name(m_provider));
}

/*!
 * @return The name of the translation catalog, which can be used to
 * translate the displayName().
 */
QString Provider::trCatalog() const
{
    return ASCII(ag_provider_get_i18n_domain(m_provider));
}

/*!
 * @return The provider icon name.
 */
QString Provider::iconName() const
{
    return ASCII(ag_provider_get_icon_name(m_provider));
}

/*!
 * @return A regular expression pattern which matches all the internet domains
 * in which this type of account can be used.
 */
QString Provider::domainsRegExp() const
{
    return UTF8(ag_provider_get_domains_regex(m_provider));
}

/*!
 * @return Whether the provider supports creating one account at most.
 */
bool Provider::isSingleAccount() const
{
    return ag_provider_get_single_account(m_provider);
}

/*!
 * Check if this provider has a tag.
 *
 * @param tag Tag to look for
 *
 * @return Provider has the tag?
 */
bool Provider::hasTag(const QString &tag) const
{
    if (!m_tags) {
        // Retrieve the tags
        tags();
    }

    return m_tags->contains(tag);
}

/*!
 * Return all tags of the provider as a set.
 *
 * @return Set of tags
 */
QSet<QString> Provider::tags() const
{
    if (m_tags)
        return *m_tags;

    m_tags = new QSet<QString>;
    GList *list = ag_provider_get_tags(m_provider);
    GList *iter = list;
    while (iter != NULL) {
        m_tags->insert(UTF8(reinterpret_cast<const gchar *> (iter->data)));
        iter = g_list_next(iter);
    }
    g_list_free(list);
    return *m_tags;
}

/*!
 * @return The DOM of the whole XML provider file.
 */
const QDomDocument Provider::domDocument() const
{
    const gchar *data;

    ag_provider_get_file_contents(m_provider, &data);

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
        QString message(QStringLiteral("Parse error reading account provider file "
                              "at line %1, column %2:\n%3"));
        message = message.arg(errorLine).arg(errorColumn).arg(errorStr);
        qWarning() << __PRETTY_FUNCTION__ << message;
    }

    return doc;
}

AgProvider *Provider::provider() const
{
    return m_provider;
}

