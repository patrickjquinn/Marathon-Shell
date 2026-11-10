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
#ifndef SYNCRESULTS_H_2
#define SYNCRESULTS_H_2

#include <QDateTime>
#include <QList>
#include <QSharedPointer>
#include <QObject>
#include <QVariantList>
#include "TargetResults.h"

class QDomDocument;
class QDomElement;

namespace Buteo {

struct DatabaseResults
{
    int iLocalItemsAdded;       /*!<The number of items added to the local database*/
    int iLocalItemsModified;    /*!<The number of items updated in the local database*/
    int iLocalItemsDeleted;     /*!<The number of items deleted from the local database*/

    int iRemoteItemsAdded;      /*!<The number of items added to the remote database*/
    int iRemoteItemsModified;   /*!<The number of items updated in the remote database*/
    int iRemoteItemsDeleted;    /*!<The number of items deleted from the remote database*/

    DatabaseResults()
        : iLocalItemsAdded(0)
        , iLocalItemsModified(0)
        , iLocalItemsDeleted(0)
        , iRemoteItemsAdded(0)
        , iRemoteItemsModified(0)
        , iRemoteItemsDeleted(0)
    {}
};

class SyncResultsPrivate;

/*! \brief Contains information about a completed synchronization session.
 *
 * SyncResults consists of the sync time/date, result code and one
 * TargetResults object for each sync target/storage (calendar, bookmarks
 * etc.).
 */
class SyncResults
{
    Q_GADGET
    Q_PROPERTY(QDateTime syncTime READ syncTime CONSTANT)
    Q_PROPERTY(MajorCode majorCode READ majorCode CONSTANT)
    Q_PROPERTY(MinorCode minorCode READ minorCode CONSTANT)
    Q_PROPERTY(bool scheduled READ isScheduled CONSTANT)
    Q_PROPERTY(QString targetId READ getTargetId CONSTANT)
    Q_PROPERTY(QVariantList results READ variantTargetResults CONSTANT)

public:
    /*! \brief enum value
     *
     * Used to set the major code in *.log.xml file for profile
     */
    enum MajorCode {
        SYNC_RESULT_INVALID = -1,
        SYNC_RESULT_SUCCESS = 0,
        SYNC_RESULT_FAILED,
        SYNC_RESULT_CANCELLED
    };
    Q_ENUM(MajorCode)

    /*! \brief enum value
     *
     * Used to set the minor code in *.log.xml file for profile
     */
    enum MinorCode {
        // No error
        NO_ERROR = 0,

        // Sync completed but some unblocking issues appeared 3xx
        ITEM_FAILURES = 301,

        // Client/Configuration errors 4xx
        INTERNAL_ERROR = 401,
        AUTHENTICATION_FAILURE,
        DATABASE_FAILURE,
        PLUGIN_ERROR,
        PLUGIN_TIMEOUT,

        // Server/Network errors 5xx
        ABORTED = 501,
        CONNECTION_ERROR,
        UNSUPPORTED_SYNC_TYPE,
        UNSUPPORTED_STORAGE_TYPE,

        // Context Error Code
        LOW_BATTERY_POWER = 601,
        POWER_SAVING_MODE,
        OFFLINE_MODE,
        BACKUP_IN_PROGRESS,
        LOW_MEMORY
    };
    Q_ENUM(MinorCode)

    /*! \brief Constructs an empty sync results object.
     *
     * Sync time is set to current time, result code should be set later by
     * calling setMajorCode , setMinorCode.
     */
    SyncResults();

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    SyncResults(const SyncResults &aSource);

    /*! \brief Constructs sync results, sets sync time and result code.
     *
     * \param aTime Sync time for the results.
     * \param aMajorCode Sync result code.
     * \param aMinorCode Sync Failed Reason.
     */
    SyncResults(QDateTime aTime, MajorCode aMajorCode, MinorCode aMinorCode);

    /*! \brief Constructs sync results from XML.
     *
     * \param aRoot Root element of the XML representation.
     */
    explicit SyncResults(const QDomElement &aRoot);

    /*! \brief Destructor.
     */
    ~SyncResults();

    /*! \brief Assignment operator.
     *
     * \param aRhs Source.
     */
    SyncResults &operator=(const SyncResults &aRhs);

    /*! \brief Exports the sync results to XML.
     *
     * \param aDoc Parent document for the created XML elements. The created
     *  elements are not inserted to the document by this function, but the
     *  document is still required for creating the elements.
     * \return Root element of the created XML.
     */
    QDomElement toXml(QDomDocument &aDoc) const;

    /*! \brief Exports the sync results to QString.
     *
     * \return return the Results as xml formatted string
     */
    QString toString() const;

    /*! \brief Gets the results of all targets.
     *
     * \return List of target results.
     */
    QList<TargetResults> targetResults() const;

    /*! \brief Adds target results to this object.
     *
     * \param aResults The target results to add.
     */
    void addTargetResults(const TargetResults &aResults);

    /*! \brief Gets the sync time.
     *
     * \return Sync time.
     */
    QDateTime syncTime() const;

    /*! \brief Gets the result code.
     *
     * \return major code.
     */
    MajorCode majorCode() const;

    /*! \brief Sets the result code.
     *
     * \param aMajorCode The result code.
     */
    void setMajorCode(MajorCode aMajorCode);

    /*! \brief Gets the failed reason.
     *
     * \return failed Reason.
     */
    MinorCode minorCode() const;

    /*! \brief Sets the failed Reason.
     *
     * \param aMinorCode - minor code or the reason
     */
    void setMinorCode(MinorCode aMinorCode);


    /*! \brief Sets the remote target Id.
     *
     * \param aTargetId The remote device Id.
     */
    void setTargetId(const QString &aTargetId);

    /*! \brief Gets the remote target Id.
     */
    QString getTargetId() const;

    /*! \brief Compares two results objects by sync time.
     *
     * The object with earlier sync time is smaller.
     * \param aOther Point of comparison.
     */
    bool operator<(const SyncResults &aOther) const;

    /*! \brief Sets if the results are from a scheduled sync.
     *
     * \param aScheduled True if this is a scheduled sync.
     */
    void setScheduled(bool aScheduled);

    /*! \brief Checks if the results are from a scheduled sync.
     *
     * \return True if scheduled.
     */
    bool isScheduled() const;

private:
    QVariantList variantTargetResults() const;
    QSharedPointer<SyncResultsPrivate> d_ptr;

#ifdef SYNCFW_UNIT_TESTS
    friend class ClientThreadTest;
#endif
};

}

Q_DECLARE_METATYPE(Buteo::SyncResults)

#endif // SYNCRESULTS_H_2
