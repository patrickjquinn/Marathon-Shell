// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
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

#ifndef LOGMACROS_H
#define LOGMACROS_H

#include "Logger.h"

/*!
 * Creates a trace message to log when the function is entered and exited.
 * Logs also to time spent in the function.
 */
#define FUNCTION_CALL_TRACE(loggingCategory) \
    QScopedPointer<Buteo::LogTimer> timerDebugVariable( \
            Buteo::isLoggingEnabled(loggingCategory()) \
            ? new Buteo::LogTimer(QString::fromUtf8(loggingCategory().categoryName()), QString(Q_FUNC_INFO)) \
            : nullptr)

#endif // LOGMACROS_H
