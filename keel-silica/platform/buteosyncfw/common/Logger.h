// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2013 - 2021 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (C) 2013 - 2021 Jolla Ltd.
 *
 * Contact: Sateesh Kavuri <sateesh.kavuri@nokia.com>
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
 *
 */


#ifndef LOGGER_H
#define LOGGER_H

#include <QLoggingCategory>
#include <QElapsedTimer>

namespace Buteo {

/*!
 * \brief Helper class for timing function execution time.
 */
class LogTimer
{
public:
    /*!
    * \brief Constructor. Creates an entry message to the log.
    *
    * @param func Name of the function.
    */
    LogTimer(const QString &categoryName, const QString &func);

    /*!
     * \brief Destructor. Creates an exit message to the log, including
     *        function execution time.
     */
    ~LogTimer();

private:
    QElapsedTimer m_timer;
    QByteArray m_categoryName;
    QString m_func;
    QLoggingCategory m_category;
};

bool isLoggingEnabled(const QLoggingCategory &loggingCategory);

void configureLegacyLogging();

}

Q_DECLARE_LOGGING_CATEGORY(lcButeoCore)
Q_DECLARE_LOGGING_CATEGORY(lcButeoMsyncd)
Q_DECLARE_LOGGING_CATEGORY(lcButeoPlugin)
Q_DECLARE_LOGGING_CATEGORY(lcButeoTrace)

#endif // LOGGER_H
