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

#include "TargetResults.h"
#include "ProfileEngineDefs.h"
#include "LogMacros.h"

#include <QDomDocument>

namespace Buteo {

struct ItemDetails
{
    QString uid;
    TargetResults::ItemOperationStatus status;
    QString message;

    ItemDetails(): status(TargetResults::ITEM_OPERATION_SUCCEEDED) {}
    ItemDetails(const QString &aUid,
                TargetResults::ItemOperationStatus aStatus,
                const QString &aMessage)
        : uid(aUid), status(aStatus), message(aMessage) {}
    ItemDetails(const QDomElement &aRoot)
        : uid(aRoot.attribute(ATTR_UID))
        , status(aRoot.attribute(ATTR_STATUS).compare(QLatin1String("failed"),
                                                      Qt::CaseInsensitive) ? TargetResults::ITEM_OPERATION_SUCCEEDED
                                                                           : TargetResults::ITEM_OPERATION_FAILED)
        , message(aRoot.text())
    {
    }

    QDomElement toXml(QDomDocument &aDoc, const QString &aTag) const
    {
        QDomElement item = aDoc.createElement(aTag);
        item.setAttribute(ATTR_UID, uid);
        if (status == TargetResults::ITEM_OPERATION_FAILED) {
            item.setAttribute(ATTR_STATUS, QLatin1String("failed"));
        }
        if (!message.isEmpty()) {
            item.appendChild(aDoc.createCDATASection(message));
        }
        return item;
    }

    static QList<ItemDetails> fromXml(const QDomElement &aRoot, const QString &aTag)
    {
        QList<ItemDetails> out;
        QDomElement item = aRoot.firstChildElement(aTag);
        while (!item.isNull()) {
            ItemDetails details(item);
            if (!details.uid.isEmpty()) {
                out.append(details);
            }
            item = item.nextSiblingElement(aTag);
        };
        return out;
    }

    static QList<QString> filterStatus(const QList<ItemDetails> &aList,
                                       TargetResults::ItemOperationStatus aStatus)
    {
        QList<QString> out;
        for (const ItemDetails &details : aList) {
            if (details.status == aStatus) {
                out.append(details.uid);
            }
        }
        return out;
    };

    static bool find(const QList<ItemDetails> &aList, const QString &aUid,
                     QList<ItemDetails>::ConstIterator &it)
    {
        for (it = aList.constBegin(); it != aList.constEnd(); ++it) {
            if (it->uid == aUid) {
                return true;
            }
        }
        return false;
    }
};

// Private implementation class for TargetResults
class TargetResultsPrivate
{
public:
    TargetResultsPrivate();

    TargetResultsPrivate(const TargetResultsPrivate &aSource);

    // Target name.
    QString iTargetName;

    ItemCounts iLocalItems;
    QList<ItemDetails> iLocalAdditions;
    QList<ItemDetails> iLocalDeletions;
    QList<ItemDetails> iLocalModifications;

    ItemCounts iRemoteItems;
    QList<ItemDetails> iRemoteAdditions;
    QList<ItemDetails> iRemoteDeletions;
    QList<ItemDetails> iRemoteModifications;
};

}

using namespace Buteo;

TargetResultsPrivate::TargetResultsPrivate()
{
}

TargetResultsPrivate::TargetResultsPrivate(const TargetResultsPrivate &aSource)
    : iTargetName(aSource.iTargetName)
    , iLocalItems(aSource.iLocalItems)
    , iLocalAdditions(aSource.iLocalAdditions)
    , iLocalDeletions(aSource.iLocalDeletions)
    , iLocalModifications(aSource.iLocalModifications)
    , iRemoteItems(aSource.iRemoteItems)
    , iRemoteAdditions(aSource.iRemoteAdditions)
    , iRemoteDeletions(aSource.iRemoteDeletions)
    , iRemoteModifications(aSource.iRemoteModifications)
{
}

TargetResults::TargetResults()
    : d_ptr(new TargetResultsPrivate())
{
}

TargetResults::TargetResults(const TargetResults &aSource)
    : d_ptr(new TargetResultsPrivate(*aSource.d_ptr))
{
}

TargetResults::TargetResults(const QString &aTargetName,
                             ItemCounts aLocalItems, ItemCounts aRemoteItems)
    : d_ptr(new TargetResultsPrivate())
{
    d_ptr->iTargetName = aTargetName;
    d_ptr->iLocalItems = aLocalItems;
    d_ptr->iRemoteItems = aRemoteItems;
}

TargetResults::TargetResults(const QDomElement &aRoot)
    : d_ptr(new TargetResultsPrivate())
{
    d_ptr->iTargetName = aRoot.attribute(ATTR_NAME);

    QDomElement local = aRoot.firstChildElement(TAG_LOCAL);
    if (!local.isNull()) {
        d_ptr->iLocalItems.added = local.attribute(ATTR_ADDED).toUInt();
        d_ptr->iLocalItems.deleted = local.attribute(ATTR_DELETED).toUInt();
        d_ptr->iLocalItems.modified = local.attribute(ATTR_MODIFIED).toUInt();
        d_ptr->iLocalAdditions = ItemDetails::fromXml(local, TAG_ADDED_ITEM);
        d_ptr->iLocalDeletions = ItemDetails::fromXml(local, TAG_DELETED_ITEM);
        d_ptr->iLocalModifications = ItemDetails::fromXml(local, TAG_MODIFIED_ITEM);
    }

    QDomElement remote = aRoot.firstChildElement(TAG_REMOTE);
    if (!remote.isNull()) {
        d_ptr->iRemoteItems.added = remote.attribute(ATTR_ADDED).toUInt();
        d_ptr->iRemoteItems.deleted = remote.attribute(ATTR_DELETED).toUInt();
        d_ptr->iRemoteItems.modified = remote.attribute(ATTR_MODIFIED).toUInt();
        d_ptr->iRemoteAdditions = ItemDetails::fromXml(remote, TAG_ADDED_ITEM);
        d_ptr->iRemoteDeletions = ItemDetails::fromXml(remote, TAG_DELETED_ITEM);
        d_ptr->iRemoteModifications = ItemDetails::fromXml(remote, TAG_MODIFIED_ITEM);
    }
}

TargetResults::~TargetResults()
{
    delete d_ptr;
    d_ptr = nullptr;
}

TargetResults &TargetResults::operator=(const TargetResults &aRhs)
{
    if (&aRhs != this) {
        delete d_ptr;
        d_ptr = new TargetResultsPrivate(*aRhs.d_ptr);
    }

    return *this;
}

QDomElement TargetResults::toXml(QDomDocument &aDoc) const
{
    QDomElement root = aDoc.createElement(TAG_TARGET_RESULTS);
    root.setAttribute(ATTR_NAME, d_ptr->iTargetName);

    QDomElement local = aDoc.createElement(TAG_LOCAL);
    local.setAttribute(ATTR_ADDED, d_ptr->iLocalItems.added);
    local.setAttribute(ATTR_DELETED, d_ptr->iLocalItems.deleted);
    local.setAttribute(ATTR_MODIFIED, d_ptr->iLocalItems.modified);
    for (const ItemDetails &details : d_ptr->iLocalAdditions) {
        local.appendChild(details.toXml(aDoc, TAG_ADDED_ITEM));
    }
    for (const ItemDetails &details : d_ptr->iLocalDeletions) {
        local.appendChild(details.toXml(aDoc, TAG_DELETED_ITEM));
    }
    for (const ItemDetails &details : d_ptr->iLocalModifications) {
        local.appendChild(details.toXml(aDoc, TAG_MODIFIED_ITEM));
    }
    root.appendChild(local);

    QDomElement remote = aDoc.createElement(TAG_REMOTE);
    remote.setAttribute(ATTR_ADDED, d_ptr->iRemoteItems.added);
    remote.setAttribute(ATTR_DELETED, d_ptr->iRemoteItems.deleted);
    remote.setAttribute(ATTR_MODIFIED, d_ptr->iRemoteItems.modified);
    for (const ItemDetails &details : d_ptr->iRemoteAdditions) {
        remote.appendChild(details.toXml(aDoc, TAG_ADDED_ITEM));
    }
    for (const ItemDetails &details : d_ptr->iRemoteDeletions) {
        remote.appendChild(details.toXml(aDoc, TAG_DELETED_ITEM));
    }
    for (const ItemDetails &details : d_ptr->iRemoteModifications) {
        remote.appendChild(details.toXml(aDoc, TAG_MODIFIED_ITEM));
    }
    root.appendChild(remote);

    return root;
}

QString TargetResults::targetName() const
{
    return d_ptr->iTargetName;
}

ItemCounts TargetResults::localItems() const
{
    return d_ptr->iLocalItems;
}

ItemCounts TargetResults::remoteItems() const
{
    return d_ptr->iRemoteItems;
}

void TargetResults::addLocalDetails(const QString &aUid,
                                    Buteo::TargetResults::ItemOperation aOperation,
                                    Buteo::TargetResults::ItemOperationStatus aStatus,
                                    const QString &aMessage)
{
    if (aUid.isEmpty()) {
        qCWarning(lcButeoCore) << "Cannot add details with empty uid.";
        return;
    }
    switch (aOperation) {
    case ITEM_ADDED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iLocalItems.added += 1;
        d_ptr->iLocalAdditions.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    case ITEM_DELETED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iLocalItems.deleted += 1;
        d_ptr->iLocalDeletions.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    case ITEM_MODIFIED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iLocalItems.modified += 1;
        d_ptr->iLocalModifications.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    };
}

void TargetResults::addRemoteDetails(const QString &aUid,
                                     Buteo::TargetResults::ItemOperation aOperation,
                                     Buteo::TargetResults::ItemOperationStatus aStatus,
                                     const QString &aMessage)
{
    if (aUid.isEmpty()) {
        qCWarning(lcButeoCore) << "Cannot add details with empty uid.";
        return;
    }
    switch (aOperation) {
    case ITEM_ADDED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iRemoteItems.added += 1;
        d_ptr->iRemoteAdditions.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    case ITEM_DELETED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iRemoteItems.deleted += 1;
        d_ptr->iRemoteDeletions.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    case ITEM_MODIFIED:
        if (aStatus == Buteo::TargetResults::ITEM_OPERATION_SUCCEEDED)
            d_ptr->iRemoteItems.modified += 1;
        d_ptr->iRemoteModifications.append(ItemDetails(aUid, aStatus, aMessage));
        break;
    };
}

QList<QString> TargetResults::localDetails(Buteo::TargetResults::ItemOperation aOperation,
                                           Buteo::TargetResults::ItemOperationStatus aStatus) const
{
    switch (aOperation) {
    case ITEM_ADDED:
        return ItemDetails::filterStatus(d_ptr->iLocalAdditions, aStatus);
    case ITEM_DELETED:
        return ItemDetails::filterStatus(d_ptr->iLocalDeletions, aStatus);
    case ITEM_MODIFIED:
        return ItemDetails::filterStatus(d_ptr->iLocalModifications, aStatus);
    }

    return QList<QString>();
}

QString TargetResults::localMessage(const QString &aUid) const
{
    QList<ItemDetails>::ConstIterator it;
    if (ItemDetails::find(d_ptr->iLocalAdditions, aUid, it)) {
        return it->message;
    } else if (ItemDetails::find(d_ptr->iLocalDeletions, aUid, it)) {
        return it->message;
    } else if (ItemDetails::find(d_ptr->iLocalModifications, aUid, it)) {
        return it->message;
    }
    return QString();
}

QList<QString> TargetResults::remoteDetails(Buteo::TargetResults::ItemOperation aOperation,
                                            Buteo::TargetResults::ItemOperationStatus aStatus) const
{
    switch (aOperation) {
    case ITEM_ADDED:
        return ItemDetails::filterStatus(d_ptr->iRemoteAdditions, aStatus);
    case ITEM_DELETED:
        return ItemDetails::filterStatus(d_ptr->iRemoteDeletions, aStatus);
    case ITEM_MODIFIED:
        return ItemDetails::filterStatus(d_ptr->iRemoteModifications, aStatus);
    };
    return QList<QString>();
}

QString TargetResults::remoteMessage(const QString &aUid) const
{
    QList<ItemDetails>::ConstIterator it;
    if (ItemDetails::find(d_ptr->iRemoteAdditions, aUid, it)) {
        return it->message;
    } else if (ItemDetails::find(d_ptr->iRemoteDeletions, aUid, it)) {
        return it->message;
    } else if (ItemDetails::find(d_ptr->iRemoteModifications, aUid, it)) {
        return it->message;
    }
    return QString();
}
