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
#ifndef SYNCSCHEDULE_H
#define SYNCSCHEDULE_H

#include <QTime>
#include <QFlags>
#include <QObject>

class QDomDocument;
class QDomElement;

namespace Buteo {

class SyncSchedulePrivate;
class SyncScheduleTest;

const QString SYNC_SCHEDULE_ENABLED_KEY_BOOL("scheduler/schedule_enabled");
const QString SYNC_SCHEDULE_PEAK_ENABLED_KEY_BOOL("scheduler/schedule_peak_enabled");
const QString SYNC_SCHEDULE_OFFPEAK_ENABLED_KEY_BOOL("scheduler/schedule_offpeak_enabled");
const QString SYNC_SCHEDULE_PEAK_DAYS_KEY_INT ("scheduler/schedule_peak_days");
const QString SYNC_SCHEDULE_PEAK_START_TIME_KEY_INT ("scheduler/schedule_peak_start_time");
const QString SYNC_SCHEDULE_PEAK_END_TIME_KEY_INT ("scheduler/schedule_peak_end_time");
const QString SYNC_SCHEDULE_PEAK_SCHEDULE_KEY_INT ("scheduler/schedule_peak");
const QString SYNC_SCHEDULE_OFFPEAK_SCHEDULE_KEY_INT ("scheduler/schedule_off_peak");

/*! \brief Class for handling sync schedule settings.
 *
 */
class SyncSchedule
{
    Q_GADGET
    Q_PROPERTY(QTime time READ time)
    Q_PROPERTY(Days days READ days)
    Q_PROPERTY(unsigned interval READ interval)
    Q_PROPERTY(bool enabled READ scheduleEnabled)
    Q_PROPERTY(QTime rushBegin READ rushBegin)
    Q_PROPERTY(QTime rushEnd READ rushEnd)
    Q_PROPERTY(Days rushDays READ rushDays)
    Q_PROPERTY(unsigned rushInterval READ rushInterval)
    Q_PROPERTY(bool rushEnabled READ rushEnabled)
public:
    enum Day {
        NoDays    = 0x00,
        Monday    = 0x01,
        Tuesday   = 0x02,
        Wednesday = 0x04,
        Thursday  = 0x08,
        Friday    = 0x10,
        Saturday  = 0x20,
        Sunday    = 0x40
    };
    Q_DECLARE_FLAGS(Days, Day)
    Q_FLAG(Days)

    /*! \brief Constructs an empty schedule.
     *
     */
    SyncSchedule();

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    SyncSchedule(const SyncSchedule &aSource);

    /*! \brief Constructs sync schedule from XML.
     *
     * \param aRoot Root element of the XML representation.
     */
    explicit SyncSchedule(const QDomElement &aRoot);

    /*! \brief Destructor.
     */
    ~SyncSchedule();

    /*! \brief Assignment operator.
     *
     * \param aRhs Source
     */
    SyncSchedule &operator=(const SyncSchedule &aRhs);

    /*! \brief Equal to operator.
     *
     * \param aRhs Source
     */
    bool operator==(const SyncSchedule &aRhs) const;

    /*! \brief Exports the sync schedule to XML.
     *
     * \param aDoc Parent document for the created XML elements.
     * \return Root element of the created XML.
     */
    QDomElement toXml(QDomDocument &aDoc) const;

    /*! \brief Exports the sync schedule to QString.
     *
     * \return return the Schedule as xml formatted string
     */
    QString toString() const;

    /*! \brief Gets the enabled week days of the sync schedule.
     *
     * Enabled week days are provided as a bitwise OR of SyncSchedule::Day.
     * \return Set of week days.
     */
    Days days() const;

    /*! \brief Sets the enabled week days.
     *
     * \param aDays Set of enabled week days.
     */
    void setDays(Days aDays);

    /*! \brief Gets the exact time set in sync schedule.
     *
     * \return Sync time. Null object if time has not been defined.
     */
    QTime time() const;

    /*! \brief Sets the exact time for sync.
     *
     * Set to null object QTime() to disable syncing at exact time.
     * \param aTime Sync time.
     */
    void setTime(const QTime &aTime);

    /*! \brief Sets scheduled config time.
    *
    * \param aDateTime Sync time.
    */
    void setScheduleConfiguredTime(const QDateTime &aDateTime);

    /*! \brief To get the scheduled config time.
    *
    *   \return QDateTime Sync time.
    */
    QDateTime scheduleConfiguredTime();

    /*! \brief Gets sync interval in minutes.
     *
     * \return Interval.
     */
    unsigned interval() const;

    /*! \brief Sets sync interval in minutes.
     *
     * Set to zero to disable syncing with intervals.
     * \param aInterval Interval.
     */
    void setInterval(unsigned aInterval);

    /*! \brief Checks if normal schedule is obeyed.
     *
     * \return Normal schedule is obeyed. Return value false corresponds to "manual" mode.
     */
    bool scheduleEnabled() const;

    /*! \brief Sets if normal schedule is to be obeyed.
     *
     * \param aEnabled Specify if normal scheduling hours enabled. If set to false, corresponds to "manual" mode.
     */
    void setScheduleEnabled(bool aEnabled);

    // ============== RUSH HOUR SETTINGS ============================


    /*! \brief Checks if rush hour schedule is to be obeyed.
     *
     * \return True if rush hour schedule is to be used. False, if rush hour scheduling is off (i.e. manual mode).
     */
    bool rushEnabled() const;

    /*! \brief Sets rush hour schedule is to be obeyed.
     *
     * \param aEnabled If set to false, corresponds to rush hour scheduling off, i.e. "manual" sync.
     */
    void setRushEnabled(bool aEnabled);

    /*! \brief Checks if rush schedule is controlled by a external process.
     *
     * \return True if rush hour schedule is to be used by a external process, The external process will control the sync, buteo will just
     * controll the schedule outside rush hours and will be responsible to switch from rush to no-rush(and vice-versa) modes.
     * False, if rush hour scheduling is controlled by this process or if rush hour scheduling is off (i.e. manual mode).
     */
    bool syncExternallyDuringRush() const;

    /*! \brief Sets if rush schedule is controlled by a external process.
     *
     * \param aEnabled If set to true, corresponds to external rush hour scheduling on, i.e. sync controlled by a external process.
     */
    void setSyncExternallyDuringRush(bool aEnabled);

    /*! \brief Gets days enabled for rush hours.
     *
     * \return Set of days enabled for rush hours.
     */
    Days rushDays() const;

    /*! \brief Sets days enabled for rush hours.
     *
     * \param aDays Enabled days for rush hours.
     */
    void setRushDays(Days aDays);

    /*! \brief Gets begin time of rush hours.
     *
     * \return Begin time.
     */
    QTime rushBegin() const;

    /*! \brief Gets end time of rush hours.
     *
     * \return End time.
     */
    QTime rushEnd() const;

    /*! \brief Sets begin and end times of rush hours.
     *
     * \param aBegin Begin time.
     * \param aEnd End time.
     */
    void setRushTime(const QTime &aBegin, const QTime &aEnd);

    /*! \brief Gets sync interval for rush hours.
     *
     * \return Interval in minutes.
     */
    unsigned rushInterval() const;

    /*! \brief Sets sync interval for rush hours.
     *
     * \param aInterval Interval.
     */
    void setRushInterval(unsigned aInterval);

    /*! \brief Checks if a given time is inside rush hour and if the sync is controlled by a external process.
     *
     * \param aDateTime DateTime to check.
     */
    bool inExternalSyncRushPeriod(const QDateTime &aDateTime) const;

    /*! \brief Gets next sync time based on the sync schedule settings.
     *
     * \param aPrevSync Previous sync time.
     * \return Next sync time. Null object if schedule is not defined.
     */
    QDateTime nextSyncTime(const QDateTime &aPrevSync) const;

    /*! \brief Gets next time to switch rush/off-rush schedule intervals.
     *
     * \param aFromTime From time to calculate next switch, usually current time.
     * \return Next time to switch rush/off-rush schedule intervals. Null object if schedule is not defined for rush/off-rush
     *  or if the rush and off-rush intervals are the same.
     */
    QDateTime nextRushSwitchTime(const QDateTime &aFromTime) const;

    /*! \brief Returns true if aDateTime is within a scheduled period.
     *
     * \param aActualDateTime the actual sync date time to be tested.
     * \param aPreviousSyncTime the previous sync time, for calculation where a sync interval is used.
     * \return true if at aActualDateTime, the synchronization is possible.
     */
    bool isSyncScheduled(const QDateTime &aActualDateTime, const QDateTime &aPreviousSyncTime = QDateTime()) const;

private:
    SyncSchedulePrivate *d_ptr;

#ifdef SYNCFW_UNIT_TESTS
    friend class SyncScheduleTest;
#endif

};

}

Q_DECLARE_METATYPE(Buteo::SyncSchedule)

#endif // SYNCSCHEDULE_H
