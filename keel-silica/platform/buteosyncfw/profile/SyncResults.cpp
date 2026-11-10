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
#include "SyncResults.h"
#include "LogMacros.h"
#include "ProfileEngineDefs.h"

#include <QDomDocument>

namespace Buteo {

//! Private implementation class for SyncResults.
class SyncResultsPrivate
{
public:
    //! Default Constructors
    SyncResultsPrivate();

    //! Copy Constructor
    SyncResultsPrivate(const SyncResultsPrivate &aSource);

    //! List of target results.
    QList<TargetResults> iTargetResults;

    //! Sync time.
    QDateTime iTime;

    SyncResults::MajorCode iMajorCode;
    SyncResults::MinorCode iMinorCode;

    //! Sync target id
    QString iTargetId;

    //! Are results for Scheduled Sync
    bool iScheduled;
};

SyncResultsPrivate::SyncResultsPrivate()
    : iTime(QDateTime::currentDateTime())
    , iMajorCode(SyncResults::SYNC_RESULT_SUCCESS)
    , iMinorCode(SyncResults::NO_ERROR)
    , iScheduled(false)
{
}

SyncResultsPrivate::SyncResultsPrivate(const SyncResultsPrivate &aSource)
    : iTargetResults(aSource.iTargetResults)
    , iTime(aSource.iTime)
    , iMajorCode(aSource.iMajorCode)
    , iMinorCode(aSource.iMinorCode)
    , iTargetId(aSource.iTargetId)
    , iScheduled(aSource.iScheduled)
{
}

}

using namespace Buteo;

SyncResults::SyncResults()
    : d_ptr(new SyncResultsPrivate())
{
}

SyncResults::SyncResults(const SyncResults &aSource)
    : d_ptr(new SyncResultsPrivate(*aSource.d_ptr))
{
}

SyncResults::SyncResults(QDateTime aTime, SyncResults::MajorCode aMajorCode, SyncResults::MinorCode aMinorCode)
    : d_ptr(new SyncResultsPrivate())
{
    d_ptr->iTime = aTime;
    d_ptr->iMajorCode = aMajorCode;
    d_ptr->iMinorCode = aMinorCode;
}

SyncResults::SyncResults(const QDomElement &aRoot)
    : d_ptr(new SyncResultsPrivate())
{
    d_ptr->iTime = QDateTime::fromString(aRoot.attribute(ATTR_TIME), Qt::ISODate);
    d_ptr->iMajorCode = static_cast<SyncResults::MajorCode>(aRoot.attribute(ATTR_MAJOR_CODE).toInt());
    d_ptr->iMinorCode = static_cast<SyncResults::MinorCode>(aRoot.attribute(ATTR_MINOR_CODE).toInt());
    d_ptr->iScheduled = (aRoot.attribute(KEY_SYNC_SCHEDULED) == BOOLEAN_TRUE);

    QDomElement target = aRoot.firstChildElement(TAG_TARGET_RESULTS);
    for (; !target.isNull();
            target = target.nextSiblingElement(TAG_TARGET_RESULTS)) {
        d_ptr->iTargetResults.append(TargetResults(target));
    }
}

SyncResults::~SyncResults()
{
}

SyncResults &SyncResults::operator=(const SyncResults &aRhs)
{
    if (&aRhs != this) {
        d_ptr = aRhs.d_ptr;
    }

    return *this;
}

QDomElement SyncResults::toXml(QDomDocument &aDoc) const
{
    QDomElement root = aDoc.createElement(TAG_SYNC_RESULTS);
    root.setAttribute(ATTR_TIME, d_ptr->iTime.toString(Qt::ISODate));
    root.setAttribute(ATTR_MAJOR_CODE, QString::number(d_ptr->iMajorCode));
    root.setAttribute(ATTR_MINOR_CODE, QString::number(d_ptr->iMinorCode));
    root.setAttribute(KEY_SYNC_SCHEDULED, d_ptr->iScheduled ? BOOLEAN_TRUE : BOOLEAN_FALSE);

    foreach (TargetResults tr, d_ptr->iTargetResults) {
        root.appendChild(tr.toXml(aDoc));
    }

    return root;
}

QString SyncResults::toString() const
{
    QDomDocument doc;
    QDomProcessingInstruction xmlHeading
        = doc.createProcessingInstruction("xml",
                                          "version=\"1.0\" encoding=\"UTF-8\"");
    doc.appendChild(xmlHeading);
    QDomElement root = toXml(doc);
    doc.appendChild(root);

    return doc.toString(PROFILE_INDENT);
}

QList<TargetResults> SyncResults::targetResults() const
{
    return d_ptr->iTargetResults;
}

QVariantList SyncResults::variantTargetResults() const
{
    QVariantList out;
    for (const TargetResults &result : d_ptr->iTargetResults) {
        out << QVariant::fromValue(result);
    }
    return out;
}

void SyncResults::addTargetResults(const TargetResults &aResults)
{
    d_ptr->iTargetResults.append(aResults);
}

QDateTime SyncResults::syncTime() const
{
    return d_ptr->iTime;
}

SyncResults::MajorCode SyncResults::majorCode() const
{
    return d_ptr->iMajorCode;
}

void SyncResults::setMajorCode(SyncResults::MajorCode aMajorCode)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    d_ptr->iMajorCode = aMajorCode;
}

SyncResults::MinorCode SyncResults::minorCode() const
{
    return d_ptr->iMinorCode;
}

void SyncResults::setMinorCode(SyncResults::MinorCode aMinorCode)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    d_ptr->iMinorCode = aMinorCode;
}

void SyncResults::setTargetId(const QString &aTargetId)
{
    d_ptr->iTargetId = aTargetId;
}

QString SyncResults::getTargetId() const
{
    return d_ptr->iTargetId;
}

bool SyncResults::operator<(const SyncResults &aOther) const
{
    return (d_ptr->iTime < aOther.d_ptr->iTime);
}

void SyncResults::setScheduled(bool aScheduled)
{
    d_ptr->iScheduled = aScheduled;
}

bool SyncResults::isScheduled() const
{
    return d_ptr->iScheduled;
}
