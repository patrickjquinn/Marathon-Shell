// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
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

#include "application.h"
#include "service.h"

#undef signals
#include <libaccounts-glib.h>

using namespace Accounts;

namespace Accounts {
/*!
 * @class Application
 * @headerfile application.h Accounts/Application
 *
 * @brief Information on the client applications of libaccounts.
 *
 * @details The Application structure holds information on the client
 * applications registered with libaccounts.
 * It is instantiated by Manager::application() and Manager::applicationList().
 */
}; // namespace

Application::Application(AgApplication *application):
    m_application(application)
{
}

/*!
 * Construct an invalid application.
 */
Application::Application():
    m_application(nullptr)
{
}

/*!
 * Copy constructor. Copying an Application object is very cheap, because the
 * data is shared among copies.
 */
Application::Application(const Application &other):
    m_application(other.m_application)
{
    if (m_application != nullptr)
        ag_application_ref(m_application);
}

Application &Application::operator=(const Application &other)
{
    if (m_application == other.m_application) return *this;
    if (m_application != nullptr)
        ag_application_unref(m_application);
    m_application = other.m_application;
    if (m_application != nullptr)
        ag_application_ref(m_application);
    return *this;
}

/*!
 * Destructor.
 */
Application::~Application()
{
    if (m_application != nullptr) {
        ag_application_unref(m_application);
        m_application = nullptr;
    }
}

/*!
 * Check whether this object represents an Application.
 * @return true if the Application is a valid one.
 */
bool Application::isValid() const
{
    return m_application != nullptr;
}

/*!
 * Get the unique ID of the application. This is the name of the .application
 * file minus the .application suffix.
 * @return The application unique ID.
 */
QString Application::name() const
{
    if (Q_UNLIKELY(!isValid())) return QString();
    return UTF8(ag_application_get_name(m_application));
}

/*!
 * Get the display name of the application.
 * @return The application display name.
 */
QString Application::displayName() const
{
    QString name;
    GDesktopAppInfo *info =
        ag_application_get_desktop_app_info(m_application);
    if (Q_LIKELY(info)) {
        name = UTF8(g_app_info_get_display_name(G_APP_INFO(info)));
        g_object_unref(info);
    }
    return name;
}

/*!
 * Get the description of the application.
 * @return The application description.
 */
QString Application::description() const
{
    return UTF8(ag_application_get_description(m_application));
}

/*!
 * Get the icon name of the application.
 * @return The application icon name.
 */
QString Application::iconName() const
{
    QString iconName;
    GDesktopAppInfo *info =
        ag_application_get_desktop_app_info(m_application);
    if (Q_LIKELY(info)) {
        gchar *gIconName = g_desktop_app_info_get_string(info, "Icon");
        if (Q_LIKELY(gIconName)) {
            iconName = UTF8(gIconName);
            g_free(gIconName);
        }
        g_object_unref(info);
    }
    return iconName;
}

/*!
 * Get the .desktop file associated with this application.
 * @return The full path to the .desktop file.
 */
QString Application::desktopFilePath() const
{
    QString filePath;
    GDesktopAppInfo *info =
        ag_application_get_desktop_app_info(m_application);
    if (Q_LIKELY(info)) {
        filePath = UTF8(g_desktop_app_info_get_filename(info));
        g_object_unref(info);
    }
    return filePath;
}

/*!
 * Get the translation catalog for the texts returned by the methods of this
 * class.
 * @return The translation catalog name.
 */
QString Application::trCatalog() const
{
    return UTF8(ag_application_get_i18n_domain(m_application));
}

/*!
 * Check whether the application supports the given service.
 * @param service Instance of a Service.
 * @return whether the service is supported by this application.
 */
bool Application::supportsService(const Service &service) const
{
    return ag_application_supports_service(m_application,
                                           service.service());
}

/*!
 * Get the description from the application XML file, for the specified
 * service; if not found, get the service-type description instead.
 * @return Usage description of the service.
 */
QString Application::serviceUsage(const Service &service) const
{
    return UTF8(ag_application_get_service_usage(m_application,
                                                 service.service()));
}

AgApplication *Application::application() const
{
    return m_application;
}
