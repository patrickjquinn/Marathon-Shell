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
#ifndef TARGETRESULTS_H
#define TARGETRESULTS_H

#include <QString>
#include <QList>
#include <QObject>

class QDomDocument;
class QDomElement;

namespace Buteo {

class TargetResultsPrivate;

//! \brief Container for number of items added, deleted and modified.
struct ItemCounts
{
    Q_GADGET
    Q_PROPERTY(unsigned added MEMBER added)
    Q_PROPERTY(unsigned deleted MEMBER deleted)
    Q_PROPERTY(unsigned modified MEMBER modified)

public:
    //! No. of Items added
    unsigned added;

    //! No. of Items deleted
    unsigned deleted;

    //! No. of Items modified
    unsigned modified;

    //! Default Constructor
    ItemCounts()
        : added(0), deleted(0), modified(0)
    {}

    //! Constructor with 3 parameters
    ItemCounts(unsigned aAdded, unsigned aDeleted, unsigned aModified)
        : added(aAdded), deleted(aDeleted), modified(aModified)
    {}
};

/*! \brief Sync results for one target.
 *
 * TargetResults contains information about how many items were added, deleted
 * and modified in a specific sync target during the sync session.
 */
class TargetResults
{
    Q_GADGET
    Q_PROPERTY(QString target READ targetName)
    Q_PROPERTY(Buteo::ItemCounts local READ localItems)
    Q_PROPERTY(Buteo::ItemCounts remote READ remoteItems)
    Q_PROPERTY(QStringList localAdditions READ localAdditions)
    Q_PROPERTY(QStringList localDeletions READ localDeletions)
    Q_PROPERTY(QStringList localModifications READ localModifications)
    Q_PROPERTY(QStringList localFailures READ localFailures)
    Q_PROPERTY(QStringList remoteAdditions READ remoteAdditions)
    Q_PROPERTY(QStringList remoteDeletions READ remoteDeletions)
    Q_PROPERTY(QStringList remoteModifications READ remoteModifications)
    Q_PROPERTY(QStringList remoteFailures READ remoteFailures)

public:
    enum ItemOperation {
        ITEM_ADDED,
        ITEM_DELETED,
        ITEM_MODIFIED
    };

    enum ItemOperationStatus {
        ITEM_OPERATION_SUCCEEDED,
        ITEM_OPERATION_FAILED
    };

    TargetResults();

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    TargetResults(const TargetResults &aSource);

    /*! \brief Constructor.
     *
     * \param aTargetName Name of the target.
     * \param aLocalItems Counts of local items.
     * \param aRemoteItems Counts of remote items.
     */
    TargetResults(const QString &aTargetName, ItemCounts aLocalItems = ItemCounts(),
                  ItemCounts aRemoteItems = ItemCounts());

    /*! \brief Constructs TargetResults from XML.
     *
     * \param aRoot Root element of the XML representation.
     */
    explicit TargetResults(const QDomElement &aRoot);

    /*! \brief Destructor.
     */
    ~TargetResults();

    /*! \brief Assignment operator.
     *
     * \param aRhs Source.
     */
    TargetResults &operator=(const TargetResults &aRhs);

    /*! \brief Exports the target results to XML.
     *
     * \param aDoc Parent document for the created XML elements. The created
     *  elements are not inserted to the document by this function, but the
     *  document is still required for creating the elements.
     * \return Root element of the created XML.
     */
    QDomElement toXml(QDomDocument &aDoc) const;

    /*! \brief Gets the target name.
     *
     * \return Target name.
     */
    QString targetName() const;

    /*! \brief Gets the counts of items added, deleted and modified locally.
     *
     * \return Item counts.
     */
    ItemCounts localItems() const;

    /*! \brief Gets the counts of items added, deleted and modified at remote.
     *
     * \return Item counts.
     */
    ItemCounts remoteItems() const;

    /*! \brief Add some details on the local changes done during the sync process.
     *
     * Provide additional information per item basis on the local changes
     * done during the sync process. If the operation succeeded, the associated
     * item count is increase by one.
     *
     * \param aUid A way for a sync plugin to identify the changed item.
     * \param aOperation The operation done on the item (addition, deletion
     *  or modification).
     * \param aStatus Particular status for this item sync operation.
     * \param aMessage Additional information related to this item operation.
     */
    void addLocalDetails(const QString &aUid,
                         ItemOperation aOperation,
                         ItemOperationStatus aStatus = ITEM_OPERATION_SUCCEEDED,
                         const QString &aMessage = QString());

    /*! \brief Add some details on the remote changes done during the sync process.
     *
     * Provide additional information per item basis on the remote changes
     * done during the sync process. If the operation succeeded, the associated
     * item count is increase by one.
     *
     * \param aUid A way for a sync plugin to identify the changed item.
     * \param aOperation The operation done on the item (addition, deletion
     *  or modification).
     * \param aStatus Particular status for this item sync operation.
     * \param aMessage Additional information related to this item operation.
     */
    void addRemoteDetails(const QString &aUid,
                          ItemOperation aOperation,
                          ItemOperationStatus aStatus = ITEM_OPERATION_SUCCEEDED,
                          const QString &aMessage = QString());

    /*! \brief Gets the details, if any for changes done local during a sync process.
     *
     * \param aOperation The operation the details are related to (addition,
     *  deletion or modification).
     * \param aStatus The kind of status for the operation (success or failure).
     * \return A list of UIDs that correspond to this operation and status.
     *         The meaning of these UIDs is defined by the SyncPlugin
     *         which generated the log.
     */
    QList<QString> localDetails(ItemOperation aOperation,
                                ItemOperationStatus aStatus) const;

    /*! \brief Gets a possible message related to the a given item.
     *
     * \param aUid A UID as returned by localDetails().
     * \return A message stored in the log related to this particular item.
     */
    Q_INVOKABLE QString localMessage(const QString &aUid) const;

    /*! \brief Gets the details, if any for changes done remote during a sync process.
     *
     * \param aOperation The operation the details are related to (addition,
     *  deletion or modification).
     * \param aStatus The kind of status for the operation (success or failure).
     * \return A list of UIDs that correspond to this operation and status.
     *         The meaning of these UIDs is defined by the SyncPlugin
     *         which generated the log.
     */
    QList<QString> remoteDetails(ItemOperation aOperation,
                                 ItemOperationStatus aStatus) const;

    /*! \brief Gets a possible message related to the a given item.
     *
     * \param aUid A UID as returned by remoteDetails().
     * \return A message stored in the log related to this particular item.
     */
    Q_INVOKABLE QString remoteMessage(const QString &aUid) const;

private:
    QStringList localAdditions() const { return localDetails(ITEM_ADDED, ITEM_OPERATION_SUCCEEDED); }
    QStringList localDeletions() const { return localDetails(ITEM_DELETED, ITEM_OPERATION_SUCCEEDED); }
    QStringList localModifications() const { return localDetails(ITEM_MODIFIED, ITEM_OPERATION_SUCCEEDED); }
    QStringList localFailures() const {
        return localDetails(ITEM_ADDED, ITEM_OPERATION_FAILED)
               + localDetails(ITEM_MODIFIED, ITEM_OPERATION_FAILED)
               + localDetails(ITEM_DELETED, ITEM_OPERATION_FAILED);
    }

    QStringList remoteAdditions() const { return remoteDetails(ITEM_ADDED, ITEM_OPERATION_SUCCEEDED); }
    QStringList remoteDeletions() const { return remoteDetails(ITEM_DELETED, ITEM_OPERATION_SUCCEEDED); }
    QStringList remoteModifications() const { return remoteDetails(ITEM_MODIFIED, ITEM_OPERATION_SUCCEEDED); }
    QStringList remoteFailures() const
    {
        return remoteDetails(ITEM_ADDED, ITEM_OPERATION_FAILED)
               + remoteDetails(ITEM_MODIFIED, ITEM_OPERATION_FAILED)
               + remoteDetails(ITEM_DELETED, ITEM_OPERATION_FAILED);
    }

    TargetResultsPrivate *d_ptr;
};

}

Q_DECLARE_METATYPE(Buteo::ItemCounts)
Q_DECLARE_METATYPE(Buteo::TargetResults)

#endif // TARGETRESULTS_H
