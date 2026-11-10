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

#include <QScopedPointer>

#include "Logger.h"

using namespace Buteo;

static bool forceDisableTraceLogging = false;

LogTimer::LogTimer(const QString &categoryName, const QString &func)
    : m_categoryName(categoryName.toUtf8())
    , m_func(func)
    , m_category(m_categoryName.constData())
{
    qCDebug(m_category) << m_func << ":Entry";
    m_timer.start();
}

LogTimer::~LogTimer()
{
    qCDebug(m_category) << m_func << ":Exit, execution time:" << m_timer.elapsed() << "ms";
}

bool Buteo::isLoggingEnabled(const QLoggingCategory &loggingCategory)
{
    return loggingCategory.isDebugEnabled() && !forceDisableTraceLogging;
}

void Buteo::configureLegacyLogging()
{
    bool hasLegacyLoggingLevel = false;
    const int legacyLoggingLevel = QString(qgetenv("MSYNCD_LOGGING_LEVEL")).toInt(&hasLegacyLoggingLevel);

    if (hasLegacyLoggingLevel) {
        if (legacyLoggingLevel >= 8) {
            // LOG_TRACE: enable all logging, including trace debugs
            QLoggingCategory::setFilterRules(QStringLiteral("buteo.*=true"));
        } else if (legacyLoggingLevel == 7) {
            // LOG_DEBUG: enable all logging except for trace debugs.
            QLoggingCategory::setFilterRules(QStringLiteral("buteo.*=true"));
            forceDisableTraceLogging = true;
        } else if (legacyLoggingLevel == 6) {
            // LOG_INFO, LOG_PROTOCOL: enable logging for non-debug levels
            QLoggingCategory::setFilterRules(QStringLiteral("buteo.*.info=true"));
        }
    }
}

Q_LOGGING_CATEGORY(lcButeoCore, "buteo.core", QtWarningMsg)
Q_LOGGING_CATEGORY(lcButeoMsyncd, "buteo.msyncd", QtWarningMsg)
Q_LOGGING_CATEGORY(lcButeoPlugin, "buteo.plugin", QtWarningMsg)
Q_LOGGING_CATEGORY(lcButeoTrace, "buteo.trace", QtWarningMsg)
