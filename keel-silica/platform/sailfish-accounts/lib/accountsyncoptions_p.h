/*
 * SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ACCOUNTSYNCOPTIONS_P_H
#define ACCOUNTSYNCOPTIONS_P_H

#include "accountsyncoptions.h"

// buteo-syncfw
#include <SyncSchedule.h>
#include <SyncProfile.h>

class AccountSyncSchedulePrivate
{
public:
    AccountSyncSchedulePrivate(AccountSyncSchedule *schedule);
    ~AccountSyncSchedulePrivate();

    void setModified(bool modified);
    void setDays(AccountSyncSchedule::Days d);

    static AccountSyncSchedule *fromButeoSchedule(const Buteo::SyncProfile &profile, QObject *parent);
    static Buteo::SyncSchedule toButeoSchedule(AccountSyncSchedule *source, Buteo::SyncProfile *profile);

    static unsigned int intervalToMinutes(AccountSyncSchedule::Interval interval);
    static unsigned int longIntervalToMinutes(AccountSyncSchedule::LongInterval interval);
    static AccountSyncSchedule::Interval intervalFromMinutes(unsigned int minutes);

    QTime m_dailySyncTime;
    QTime m_peakStartTime;
    QTime m_peakEndTime;
    AccountSyncSchedule *q;
    AccountSyncSchedule::Interval m_interval;
    AccountSyncSchedule::Interval m_peakInterval;
    AccountSyncSchedule::LongInterval m_longInterval;
    AccountSyncSchedule::Days m_days;
    AccountSyncSchedule::Days m_peakDays;
    bool m_modified;
    bool m_peakEnabled;
    bool m_enabled;
    bool m_externalPeakEnabled;
};

class AccountSyncOptionsPrivate
{
public:
    AccountSyncOptionsPrivate(AccountSyncOptions *parent);

    void setModified(bool modified);

    static AccountSyncOptions *fromButeoProfile(const Buteo::SyncProfile &source, QObject *parent);

    static void writeToButeoProfile(AccountSyncOptions *options, Buteo::SyncProfile *profile);

    static unsigned int pastSyncPeriodToDays(AccountSyncOptions::PastSyncPeriod period);
    static AccountSyncOptions::PastSyncPeriod pastSyncPeriodFromDays(unsigned int dayCount);

    AccountSyncOptions *q;
    AccountSyncSchedule *m_schedule;
    AccountSyncOptions::PastSyncPeriod m_pastSyncPeriod;
    AccountSyncOptions::Direction m_direction;
    int m_allowedConnectionTypes;
    bool m_modified;
    bool m_autoSync;
    bool m_syncExternallyEnabled;
};

#endif
