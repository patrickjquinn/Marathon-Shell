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
#ifndef SYNCLOG_H
#define SYNCLOG_H

#include <QList>
#include <QString>
#include "SyncResults.h"

class QDomDocument;
class QDomElement;

namespace Buteo {

class SyncLogPrivate;
class SyncLogTest;

/*! \brief History of completed synchronization sessions and their results.
 *
 * Each SyncProfile has its own SyncLog associated to it. Loading and saving of
 * SyncLog objects is handled by the ProfileManager. SyncLog is composed of
 * SyncResults objects, one for each completed sync session.
 */
class SyncLog
{
public:
    /*! \brief Constructs an empty log with the given profile name.
     *
     * \param aProfileName Name of the profile this log is related to.
     */
    explicit SyncLog(const QString &aProfileName);

    /*! \brief Constructs a SyncLog from XML.
     *
     * \param aRoot Root element of the XML representation of the log.
     */
    explicit SyncLog(const QDomElement &aRoot);

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    SyncLog(const SyncLog &aSource);

    /*! \brief Destructor.
     *
     */
    ~SyncLog();

    /*! \brief Sets the name of the profile that owns this log.
    */
    void setProfileName(const QString &aProfileName);

    /*! \brief Gets the name of the profile that owns this log.
     *
     * \return Profile name.
     */
    QString profileName() const;

    /*! \brief Exports the log to XML.
     *
     * \param aDoc Parent document for the created XML elements. The created
     *  elements are not inserted to the document by this function, but the
     *  document is still required for creating the elements.
     * \return Root element of the created XML.
     */
    QDomElement toXml(QDomDocument &aDoc) const;

    /*! \brief Gets the most recent results in the sync log.
     *
     * \return The results. NULL if the log is empty.
     */
    const SyncResults *lastResults() const;

    /*! \brief Gets all results in the sync log.
     *
     * \return List of results. The results are ordered by time so that
     *  the oldest results object is first in the list.
     */
    QList<const SyncResults *> allResults() const;

    /*! \brief Gets the last successful results in the sync log.
     *
     * \return The results. NULL if no successful result have already
     * been registered.
     */
    const SyncResults *lastSuccessfulResults() const;

    /*! \brief Adds results to the sync log.
     *  Also makes sure that log size doesn't exceed given size limit
     *
     * \param aResults Results to add.
     */
    void addResults(const SyncResults &aResults);

private:
    SyncLog &operator=(const SyncLog &aRhs);

    SyncLogPrivate *d_ptr;
};

}

#endif // SYNCLOG_H
