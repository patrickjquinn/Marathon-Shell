// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2014-2019 Jolla Ltd
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (C) 2014-2019 Jolla Ltd.
 * Copyright (C) 2020 Open Mobile Platform LLC.
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

#include "SyncSchedule.h"
#include "SyncSchedule_p.h"
#include "ProfileEngineDefs.h"
#include "SyncCommonDefs.h"
#include "LogMacros.h"

#include <QDomDocument>
#include <QStringList>
#include <limits.h>

using namespace Buteo;

static const QString DAY_SEPARATOR = ",";

SyncSchedulePrivate::SyncSchedulePrivate()
    : iDays(SyncSchedule::NoDays)
    , iInterval(0)
    , iEnabled(false)
    , iRushDays(SyncSchedule::NoDays)
    , iRushInterval(0)
    , iRushEnabled(false)
    , iExternalRushEnabled(false)
{
}

SyncSchedulePrivate::SyncSchedulePrivate(const SyncSchedulePrivate &aSource)
    : iDays(aSource.iDays)
    , iTime(aSource.iTime)
    , iScheduleConfiguredTime(aSource.iScheduleConfiguredTime)
    , iInterval(aSource.iInterval)
    , iEnabled(aSource.iEnabled)
    , iRushDays(aSource.iRushDays)
    , iRushBegin(aSource.iRushBegin)
    , iRushEnd(aSource.iRushEnd)
    , iRushInterval(aSource.iRushInterval)
    , iRushEnabled(aSource.iRushEnabled)
    , iExternalRushEnabled(aSource.iExternalRushEnabled)
{
}

SyncSchedule::SyncSchedule()
    : d_ptr(new SyncSchedulePrivate())
{
}

SyncSchedule::SyncSchedule(const SyncSchedule &aSource)
    : d_ptr(new SyncSchedulePrivate(*aSource.d_ptr))
{
}

SyncSchedule::SyncSchedule(const QDomElement &aRoot)
    : d_ptr(new SyncSchedulePrivate())
{
    d_ptr->iTime = QTime::fromString(aRoot.attribute(ATTR_TIME), Qt::ISODate);
    d_ptr->iInterval = aRoot.attribute(ATTR_INTERVAL).toUInt();
    d_ptr->iEnabled = (aRoot.attribute(ATTR_ENABLED) == BOOLEAN_TRUE);
    d_ptr->iDays = d_ptr->parseDays(aRoot.attribute(ATTR_DAYS));
    d_ptr->iScheduleConfiguredTime = QDateTime::fromString(aRoot.attribute(ATTR_SYNC_CONFIGURE), Qt::ISODate);

    QDomElement rush = aRoot.firstChildElement(TAG_RUSH);

    if (!rush.isNull()) {
        d_ptr->iRushEnabled = (rush.attribute(ATTR_ENABLED) == BOOLEAN_TRUE);
        d_ptr->iExternalRushEnabled = (rush.attribute(ATTR_EXTERNAL_SYNC) == BOOLEAN_TRUE);
        d_ptr->iRushInterval = rush.attribute(ATTR_INTERVAL).toUInt();
        d_ptr->iRushBegin = QTime::fromString(rush.attribute(ATTR_BEGIN), Qt::ISODate);
        d_ptr->iRushEnd = QTime::fromString(rush.attribute(ATTR_END), Qt::ISODate);
        d_ptr->iRushDays = d_ptr->parseDays(rush.attribute(ATTR_DAYS));
    } else {
        d_ptr->iRushEnabled = false;
        d_ptr->iExternalRushEnabled = false;
        d_ptr->iRushInterval = 0;
    }
}

SyncSchedule::~SyncSchedule()
{
    delete d_ptr;
    d_ptr = nullptr;
}

SyncSchedule &SyncSchedule::operator=(const SyncSchedule &aRhs)
{
    if (&aRhs != this) {
        delete d_ptr;
        d_ptr = new SyncSchedulePrivate(*aRhs.d_ptr);
    }

    return *this;
}

bool SyncSchedule::operator==(const SyncSchedule &aRhs) const
{
    if (&aRhs == this)
        return true;

    return (d_ptr->iRushDays == aRhs.d_ptr->iRushDays)
           && (d_ptr->iRushBegin == aRhs.d_ptr->iRushBegin)
           && (d_ptr->iRushEnd == aRhs.d_ptr->iRushEnd)
           && (d_ptr->iRushInterval == aRhs.d_ptr->iRushInterval)
           && (d_ptr->iInterval == aRhs.d_ptr->iInterval)
           && (d_ptr->iEnabled == aRhs.d_ptr->iEnabled)
           && (d_ptr->iRushEnabled == aRhs.d_ptr->iRushEnabled)
           && (d_ptr->iExternalRushEnabled == aRhs.d_ptr->iExternalRushEnabled);
}

QDomElement SyncSchedule::toXml(QDomDocument &aDoc) const
{
    QDomElement root = aDoc.createElement(TAG_SCHEDULE);
    root.setAttribute(ATTR_ENABLED, d_ptr->iEnabled ? BOOLEAN_TRUE : BOOLEAN_FALSE);
    root.setAttribute(ATTR_TIME, d_ptr->iTime.toString(Qt::ISODate));
    root.setAttribute(ATTR_INTERVAL, QString::number(d_ptr->iInterval));
    root.setAttribute(ATTR_DAYS, d_ptr->createDays(d_ptr->iDays));
    root.setAttribute(ATTR_SYNC_CONFIGURE, d_ptr->iScheduleConfiguredTime.toString(Qt::ISODate));

    QDomElement rush = aDoc.createElement(TAG_RUSH);
    rush.setAttribute(ATTR_ENABLED, d_ptr->iRushEnabled ? BOOLEAN_TRUE : BOOLEAN_FALSE);
    rush.setAttribute(ATTR_EXTERNAL_SYNC, d_ptr->iExternalRushEnabled ? BOOLEAN_TRUE : BOOLEAN_FALSE);
    rush.setAttribute(ATTR_INTERVAL, QString::number(d_ptr->iRushInterval));
    rush.setAttribute(ATTR_BEGIN, d_ptr->iRushBegin.toString(Qt::ISODate));
    rush.setAttribute(ATTR_END, d_ptr->iRushEnd.toString(Qt::ISODate));
    rush.setAttribute(ATTR_DAYS, d_ptr->createDays(d_ptr->iRushDays));
    root.appendChild(rush);

    return root;
}

QString SyncSchedule::toString() const
{
    QDomDocument doc;
    QDomProcessingInstruction xmlHeading =
        doc.createProcessingInstruction("xml",
                                        "version=\"1.0\" encoding=\"UTF-8\"");
    doc.appendChild(xmlHeading);
    QDomElement root = toXml(doc);
    doc.appendChild(root);

    return doc.toString(PROFILE_INDENT);
}

SyncSchedule::Days SyncSchedule::days() const
{
    return d_ptr->iDays;
}

void SyncSchedule::setDays(SyncSchedule::Days aDays)
{
    d_ptr->iDays = aDays;
}

void SyncSchedule::setScheduleConfiguredTime(const QDateTime &aDateTime)
{
    d_ptr->iScheduleConfiguredTime = aDateTime;
}

QDateTime SyncSchedule::scheduleConfiguredTime()
{
    return d_ptr->iScheduleConfiguredTime;
}

QTime SyncSchedule::time() const
{
    return d_ptr->iTime;
}

void SyncSchedule::setTime(const QTime &aTime)
{
    d_ptr->iTime = aTime;
}

unsigned SyncSchedule::interval() const
{
    return d_ptr->iInterval;
}

void SyncSchedule::setInterval(unsigned aInterval)
{
    d_ptr->iInterval = aInterval;
}

bool SyncSchedule::scheduleEnabled() const
{
    return d_ptr->iEnabled;
}

void SyncSchedule::setScheduleEnabled(bool aEnabled)
{
    d_ptr->iEnabled = aEnabled;
}

bool SyncSchedule::rushEnabled() const
{
    return d_ptr->iRushEnabled;
}

void SyncSchedule::setRushEnabled(bool aEnabled)
{
    d_ptr->iRushEnabled = aEnabled;
}

bool SyncSchedule::syncExternallyDuringRush() const
{
    return d_ptr->iExternalRushEnabled;
}

void SyncSchedule::setSyncExternallyDuringRush(bool aEnabled)
{
    d_ptr->iExternalRushEnabled = aEnabled;
}

SyncSchedule::Days SyncSchedule::rushDays() const
{
    return d_ptr->iRushDays;
}

void SyncSchedule::setRushDays(SyncSchedule::Days aDays)
{
    d_ptr->iRushDays = aDays;
}

QTime SyncSchedule::rushBegin() const
{
    return d_ptr->iRushBegin;
}

QTime SyncSchedule::rushEnd() const
{
    return d_ptr->iRushEnd;
}

void SyncSchedule::setRushTime(const QTime &aBegin, const QTime &aEnd)
{
    d_ptr->iRushBegin = aBegin;
    d_ptr->iRushEnd = aEnd;
}

unsigned SyncSchedule::rushInterval() const
{
    return d_ptr->iRushInterval;
}

void SyncSchedule::setRushInterval(unsigned aInterval)
{
    d_ptr->iRushInterval = aInterval;
}

bool SyncSchedule::inExternalSyncRushPeriod(const QDateTime &aDateTime) const
{
    return d_ptr->iEnabled && d_ptr->iRushEnabled && d_ptr->iExternalRushEnabled
            && d_ptr->isRush(aDateTime);
}

QDateTime SyncSchedule::nextSyncTime(const QDateTime &aPrevSync) const
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QDateTime nextSync;
    QDateTime scheduleConfiguredTime = d_ptr->iScheduleConfiguredTime;
    QDateTime now = QDateTime::currentDateTime();

    qCDebug(lcButeoCore) << "aPrevSync" << aPrevSync.toString() << "Last Configured Time "
                         << scheduleConfiguredTime.toString() << "CurrentDateTime" << now;

    if (d_ptr->iTime.isValid() && d_ptr->iDays != SyncSchedule::NoDays) {
        // The sync time is defined explicitly (for ex. every Mon, Wed, at
        // 5:30PM). So choose the next applicable day from now.
        qCDebug(lcButeoCore) << "Explicit sync time defined.";
        nextSync.setTime(d_ptr->iTime);
        nextSync.setDate(now.date());
        if (now.time() > d_ptr->iTime) {
            nextSync = nextSync.addDays(1);
        }
        d_ptr->adjustDate(nextSync, d_ptr->iDays);
    } else if (d_ptr->iInterval > 0 && d_ptr->iEnabled) {
        // Sync time is defined in terms of interval (for ex. every 15 minutes)
        qCDebug(lcButeoCore) << "Sync interval defined as" << d_ptr->iInterval;

        // Last sync time is not available/valid (Could happen if the device
        // is shut down for an extended period before the first sync can be
        // performed). Hence use the time the
        // sync was last scheduled as the reference
        // Figure out the number of intervals passed
        QDateTime reference;
        reference = (aPrevSync.isValid()) ? aPrevSync : scheduleConfiguredTime;
        if (reference > now) {
            // If the clock was rolled back...
            qCDebug(lcButeoCore) << "Setting reference to now";
            reference = now;
        } else if (!reference.isValid()) {
            //It means configuring first time account. Need to sync now only.
            qCDebug(lcButeoCore) << "Reference is not valid returning current date time";
            return QDateTime::currentDateTime();
        }

        if (d_ptr->iInterval == Sync::SYNC_INTERVAL_MONTHLY) {
            nextSync.setDate(reference.date().addMonths(1));
            nextSync.setTime(d_ptr->iTime);

            if (QDateTime::currentDateTime().secsTo(nextSync) < 0) {
                qCDebug(lcButeoCore) << "Named interval is in the past, so sync now";
                // The next sync time has passed, so schedule it to happen shortly.
                return QDateTime::currentDateTime();
            }
        } else if (d_ptr->iInterval == Sync::SYNC_INTERVAL_FIRST_DAY_OF_MONTH
                   || d_ptr->iInterval == Sync::SYNC_INTERVAL_LAST_DAY_OF_MONTH) {
            QDate date = reference.date();
            date.setDate(date.year(), date.month(),
                         d_ptr->iInterval == Sync::SYNC_INTERVAL_FIRST_DAY_OF_MONTH ? 1 : date.daysInMonth());
            nextSync.setDate(date);
            nextSync.setTime(d_ptr->iTime);
            if (now.secsTo(nextSync) < 0) {
                qCDebug(lcButeoCore) << "Named interval to" << nextSync
                          << "is in the past, so use date for next month instead";
                // The next sync time has passed, so schedule it in the month following the
                // current date.
                while (nextSync < now) {
                    nextSync = nextSync.addMonths(1);
                }
            }

        } else {
            const int secs = reference.secsTo(now) + 1;
            const int numberOfIntervals = (secs / (d_ptr->iInterval * 60))
                                          + (((secs % (d_ptr->iInterval * 60)) != 0) ? 1 : 0);
            qCDebug(lcButeoCore) << "numberOfInterval:" << numberOfIntervals << "interval time" << d_ptr->iInterval;
            nextSync = reference.addSecs(numberOfIntervals * d_ptr->iInterval * 60);
        }
    }

    qCDebug(lcButeoCore) << "next non rush hour sync is at:: " << nextSync;

    // Rush is controlled by a external process(e.g always-up-to-date), buteo controls the switch between rush and offRush
    if (d_ptr->iRushEnabled && d_ptr->iExternalRushEnabled) {
        qCDebug(lcButeoCore) << "Rush Interval is controlled by a external process.";
        // Set next sync to rush end
        const bool isRush(d_ptr->isRush(now));
        QDateTime nextSyncRush;
        nextSyncRush.setTime(isRush ? d_ptr->iRushEnd : d_ptr->iRushBegin);
        nextSyncRush.setDate(now.date());
        if (now.time() > d_ptr->iRushEnd) {
            nextSyncRush = nextSyncRush.addDays(1);
        }
        d_ptr->adjustDate(nextSyncRush, d_ptr->iRushDays);
        qCDebug(lcButeoCore) << "Rush controlled by external process, next scheduled sync at rush "
                             << (isRush ? "end" : "begin") << nextSyncRush.toString();

        // Use next sync time calculated with rush settings if necessary.
        if (nextSyncRush.isValid()) {
            // check to see if we should use it, or instead use the next non-rush sync time.
            if (nextSync.isValid()
                    && nextSync > now
                    && nextSync < nextSyncRush
                    && (!d_ptr->isRush(nextSync))) {
                // the next non-rush sync time occurs after now
                // but before the next rush sync time, and either it
                // doesn't fall within the rush period itself or the
                // next rush sync time is in the next rush period.
                // we should use the non-rush schedule.
                qCDebug(lcButeoCore) << "Using non-rush time as the next sync time";
            } else {
                nextSync = nextSyncRush;
            }
        }
    } else if (d_ptr->iRushEnabled && d_ptr->iRushInterval > 0 && !d_ptr->iExternalRushEnabled) {
        qCDebug(lcButeoCore) << "Calculating next sync time with rush settings. Rush Interval is "
                             << d_ptr->iRushInterval;
        // Calculate next sync time with rush settings.
        QDateTime nextSyncRush;
        bool nextSyncRushInNextRushPeriod = false;
        if (d_ptr->isRush(now)) {
            qCDebug(lcButeoCore) << "Current time is in rush";
            // We are in rush hour
            if (aPrevSync.isValid()) {
                qCDebug(lcButeoCore) << "PrevSync is valid and isRush true.. ";
                nextSyncRush = aPrevSync.addSecs(d_ptr->iRushInterval * 60);
                if ((nextSyncRush < now) || (aPrevSync > now)) {
                    // Use current time if the previous sync time is too old, or
                    // the clock has been rolled back
                    nextSyncRush = now.addSecs(d_ptr->iRushInterval * 60);
                    qCDebug(lcButeoCore) << "nextsyncRush based on aPrevSync" << nextSyncRush;
                }
            } else {
                nextSyncRush = now.addSecs(d_ptr->iRushInterval * 60);
            }

            if (!d_ptr->isRush(nextSyncRush)) {
                // If the calculated rush time does not lie in the rush
                // interval, choose the next available rush time as the begin
                // time for the rush interval
                qCDebug(lcButeoCore) << "isRush False";
                nextSyncRushInNextRushPeriod = true;
                nextSyncRush.setTime(d_ptr->iRushBegin);
                if (nextSyncRush < now) {
                    nextSyncRush = nextSyncRush.addDays(1);
                }
                d_ptr->adjustDate(nextSyncRush, d_ptr->iRushDays);
            }
        } else {
            qCDebug(lcButeoCore) << "Current Time is Not Rush";
            nextSyncRush.setTime(d_ptr->iRushBegin);
            nextSyncRush.setDate(now.date());
            if (now.time() > d_ptr->iRushBegin) {
                nextSyncRush = nextSyncRush.addDays(1);
            }
            d_ptr->adjustDate(nextSyncRush, d_ptr->iRushDays);
        }

        qCDebug(lcButeoCore) << "nextSyncRush" << nextSyncRush.toString();
        // Use next sync time calculated with rush settings if necessary.
        if (nextSyncRush.isValid()) {
            // check to see if we should use it, or instead use the next non-rush sync time.
            if (nextSync.isValid()
                    && nextSync > now
                    && nextSync < nextSyncRush
                    && (!d_ptr->isRush(nextSync) || nextSyncRushInNextRushPeriod)) {
                // the next non-rush sync time occurs after now
                // but before the next rush sync time, and either it
                // doesn't fall within the rush period itself or the
                // next rush sync time is in the next rush period.
                // we should use the non-rush schedule.
                qCDebug(lcButeoCore) << "Using non-rush time as the next sync time";
            } else {
                // we should use the rush schedule.
                qCDebug(lcButeoCore) << "Using rush time as the next sync time";
                nextSync = nextSyncRush;
            }
        }
    }

    //For safer side checking nextSyncTime should not be behind currentDateTime.
    if (QDateTime::currentDateTime().secsTo(nextSync) < 0) {
        //If it is the case making it to currentTime.
        qCWarning(lcButeoCore) << "Something went wrong in nextSyncTime calculation resetting to current time";
        nextSync = QDateTime::currentDateTime();
    }

    qCDebug(lcButeoCore) << "nextSync" << nextSync.toString();
    return nextSync;
}

QDateTime SyncSchedule::nextRushSwitchTime(const QDateTime &aFromTime) const
{
    if (rushEnabled() && scheduleEnabled()) {
        if (d_ptr->iRushInterval == d_ptr->iInterval && !d_ptr->iExternalRushEnabled) {
            qCDebug(lcButeoCore) << "Rush interval is the same as normal interval no need to switch";
            return QDateTime();
        }
        if (d_ptr->isRush(aFromTime)) {
            return QDateTime(aFromTime.date(), d_ptr->iRushEnd);
        } else {
            // If rush day and before rush end next switch is at rush begin
            if (SyncSchedulePrivate::daysMatch(d_ptr->iRushDays, aFromTime.date().dayOfWeek())
                && aFromTime.time() < d_ptr->iRushBegin) {
                return QDateTime(aFromTime.date(), d_ptr->iRushBegin);
            } else {
                // Not a rush day or the rush period has ended, attemp switch at next day rush begin,
                // we can only schedule for 24h
                return QDateTime(aFromTime.date().addDays(1), d_ptr->iRushBegin);
            }
        }
    } else {
        return QDateTime();
    }
}

bool SyncSchedule::isSyncScheduled(const QDateTime &aActualDateTime, const QDateTime &aPreviousSyncTime) const
{
    qCDebug(lcButeoCore) << "Check if sync is scheduled against" << aActualDateTime.toString();

    // Simple case, aDateTime is the defined sync time.
    if (d_ptr->iTime.isValid() && d_ptr->iDays != SyncSchedule::NoDays) {
        // Accept wakeups close to the schedule for aActualDate (today), and also for previousDay (yesterday) schedule
        // when the timer crosses midnight.
        static const qint64 toleranceSecs = 5 * 60;
        qint64 minDiffSecs = LLONG_MAX;

        const QDate aActualDate = aActualDateTime.date();
        const bool actualDateMatch = SyncSchedulePrivate::daysMatch(d_ptr->iDays, aActualDate.dayOfWeek());
        if (actualDateMatch) {
            qint64 diff = qAbs(QDateTime(aActualDate, d_ptr->iTime).secsTo(aActualDateTime));
            minDiffSecs = qMin(minDiffSecs, diff);
            qCDebug(lcButeoCore) << "Scheduled check (actual): scheduled=" << QDateTime(aActualDate, d_ptr->iTime)
                                 << "actual=" << aActualDateTime << "diffSecs=" << diff;
        } else {
            qCDebug(lcButeoCore) << "Scheduled check (actual): day mismatch, scheduledDays=" << d_ptr->iDays
                                 << "actualDayOfWeek=" << aActualDate.dayOfWeek();
        }

        const QDate previousDay = aActualDate.addDays(-1);
        const bool previousDayMatch = SyncSchedulePrivate::daysMatch(d_ptr->iDays, previousDay.dayOfWeek());
        if (previousDayMatch) {
            qint64 diff = qAbs(QDateTime(previousDay, d_ptr->iTime).secsTo(aActualDateTime));
            minDiffSecs = qMin(minDiffSecs, diff);
            qCDebug(lcButeoCore) << "Scheduled check (previous): scheduled=" << QDateTime(previousDay, d_ptr->iTime)
                                 << "actual=" << aActualDateTime << "diffSecs=" << diff;
        } else {
            qCDebug(lcButeoCore) << "Scheduled check (previous): day mismatch, scheduledDays=" << d_ptr->iDays
                                 << "previousDayOfWeek=" << previousDay.dayOfWeek();
        }

        if (minDiffSecs == LLONG_MAX) {
            qCDebug(lcButeoCore) << "Scheduled check result: rejected, no matching day candidate for explicit-time schedule.";
            return false;
        }

        const bool accepted = minDiffSecs <= toleranceSecs;
        qCDebug(lcButeoCore) << "Scheduled check result:" << (accepted ? "accepted" : "rejected")
                             << "minDiffSecs=" << minDiffSecs << "toleranceSecs=" << toleranceSecs;
        return accepted;
    }

    // If sync schedule is defined by rush, check that rush is enabled for aActualDateTime
    if (rushEnabled() && d_ptr->iRushInterval > 0 && d_ptr->isRush(aActualDateTime)) {
        return true;
    }

    if (!scheduleEnabled() || !d_ptr->iInterval) {
        qCDebug(lcButeoCore) << "Scheduled by interval: schedule is disabled or not syncing by interval";
        return false;
    }

    QDateTime reference = (aPreviousSyncTime.isValid()) ? aPreviousSyncTime : d_ptr->iScheduleConfiguredTime;
    if (!reference.isValid()) {
        qCDebug(lcButeoCore) << "Schedule has no reference past date, sync now";
        return true;
    }

    qint64 longInterval = 0;
    if (d_ptr->iInterval == Sync::SYNC_INTERVAL_MONTHLY) {
        QDateTime nextSync = reference.addMonths(1);
        nextSync.setTime(d_ptr->iTime);
        longInterval = reference.secsTo(nextSync) / 60;
    } else if (d_ptr->iInterval == Sync::SYNC_INTERVAL_FIRST_DAY_OF_MONTH) {
        // Calculate interval to the first day of the month after the previous sync.
        QDate date = reference.date().addMonths(1);
        date.setDate(date.year(), date.month(), 1);
        QDateTime nextSync(date, d_ptr->iTime);
        longInterval = reference.secsTo(nextSync) / 60;
    } else if (d_ptr->iInterval == Sync::SYNC_INTERVAL_LAST_DAY_OF_MONTH) {
        // Calculate interval to the last day of the month after the previous sync.
        QDate date = reference.date();
        if (reference.date() == aActualDateTime.date()) {
            // Already synced on the last day, so calculate to the next month instead.
            date = date.addMonths(1);
        }
        QDateTime nextSync(date, d_ptr->iTime);
        longInterval = reference.secsTo(nextSync) / 60;
    }

    const unsigned int interval = longInterval > 0
                                  ? (longInterval > UINT_MAX ? UINT_MAX : static_cast<unsigned int>(longInterval))
                                  : d_ptr->iInterval;

    // avoid wrap-around: don't subtract from unsigned interval
    return reference.secsTo(aActualDateTime) > (interval * 60);
}

SyncSchedule::Days SyncSchedulePrivate::parseDays(const QString &aDays) const
{
    SyncSchedule::Days days; // Modified by Shipwright for Qt 6: a QFlags starts empty
    const SyncSchedule::Day fromStrDays[] =
        {SyncSchedule::Monday, SyncSchedule::Tuesday,
         SyncSchedule::Wednesday, SyncSchedule::Thursday,
         SyncSchedule::Friday, SyncSchedule::Saturday,
         SyncSchedule::Sunday};
    if (!aDays.isNull()) {
        QStringList dayList = aDays.split(DAY_SEPARATOR,
                                          Qt::SkipEmptyParts); // Modified by Shipwright for Qt 6
        foreach (QString dayStr, dayList) {
            bool ok;
            int dayNum = dayStr.toInt(&ok);
            if (ok && dayNum > 0 && dayNum <= 7) {
                days |= fromStrDays[dayNum - 1];
            }
        }
    }

    return days;
}

QString SyncSchedulePrivate::createDays(SyncSchedule::Days aDays) const
{
    QStringList dayList;

    if (aDays & SyncSchedule::Monday) {
        dayList.append(QString::fromLatin1("1"));
    }
    if (aDays & SyncSchedule::Tuesday) {
        dayList.append(QString::fromLatin1("2"));
    }
    if (aDays & SyncSchedule::Wednesday) {
        dayList.append(QString::fromLatin1("3"));
    }
    if (aDays & SyncSchedule::Thursday) {
        dayList.append(QString::fromLatin1("4"));
    }
    if (aDays & SyncSchedule::Friday) {
        dayList.append(QString::fromLatin1("5"));
    }
    if (aDays & SyncSchedule::Saturday) {
        dayList.append(QString::fromLatin1("6"));
    }
    if (aDays & SyncSchedule::Sunday) {
        dayList.append(QString::fromLatin1("7"));
    }

    return dayList.join(DAY_SEPARATOR);
}

bool SyncSchedulePrivate::daysMatch(SyncSchedule::Days aDays, int aDay)
{
    const SyncSchedule::Day fromQtDays[] =
        {SyncSchedule::Monday, SyncSchedule::Tuesday,
         SyncSchedule::Wednesday, SyncSchedule::Thursday,
         SyncSchedule::Friday, SyncSchedule::Saturday,
         SyncSchedule::Sunday};

    return aDay >= Qt::Monday && aDay <= Qt::Sunday && (aDays & fromQtDays[aDay - 1]);
}

bool SyncSchedulePrivate::adjustDate(QDateTime &aTime, SyncSchedule::Days aDays) const
{
    if (aDays == SyncSchedule::NoDays) {
        aTime = QDateTime();
        return false;
    }

    bool newValidDay = false;
    int startDay = aTime.date().dayOfWeek();
    while (!daysMatch(aDays, aTime.date().dayOfWeek())) {
        newValidDay = true;
        aTime = aTime.addDays(1);
        // Safety check, avoid infinite loop if date set contains
        // only invalid values.
        if (aTime.date().dayOfWeek() == startDay) {
            // Clear next sync time.
            newValidDay = false;
            aTime = QDateTime();
            break;
        }
    }

    return newValidDay;
}

bool SyncSchedulePrivate::isRush(const QDateTime &aTime) const
{
    return (daysMatch(iRushDays, aTime.date().dayOfWeek())
            && aTime.time() >= iRushBegin && aTime.time() < iRushEnd);
}
