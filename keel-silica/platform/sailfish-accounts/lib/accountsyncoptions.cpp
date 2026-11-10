// SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "accountsyncoptions_p.h"

// buteo-syncfw
#include <ProfileEngineDefs.h>
#include <SyncCommonDefs.h>

#include <QDebug>
#include <QSet>
#include <QList>

namespace {

const AccountSyncOptions::PastSyncPeriod DefaultPastSyncPeriod = AccountSyncOptions::OneMonthAgo;
const AccountSyncOptions::Direction DefaultDirection = AccountSyncOptions::TwoWaySync;
const bool DefaultAutomaticSync = true;

} // anon namespace


AccountSyncSchedulePrivate::AccountSyncSchedulePrivate(AccountSyncSchedule *schedule)
    : q(schedule)
    , m_interval(AccountSyncSchedule::NoInterval)
    , m_peakInterval(AccountSyncSchedule::Every15Minutes)
    , m_longInterval(AccountSyncSchedule::NoLongInterval)
    , m_days(AccountSyncSchedule::everyday())
    , m_peakDays(0)
    , m_modified(false)
    , m_peakEnabled(false)
    , m_enabled(false)
    , m_externalPeakEnabled(false)
{
}

AccountSyncSchedulePrivate::~AccountSyncSchedulePrivate()
{
}

void AccountSyncSchedulePrivate::setModified(bool modified)
{
    if (modified != m_modified) {
        m_modified = modified;
        emit q->modifiedChanged();
    }
}

void AccountSyncSchedulePrivate::setDays(AccountSyncSchedule::Days d)
{
    if (m_days != d) {
        m_days = d;
        emit q->daysChanged();
        setModified(true);
    }
}

unsigned int AccountSyncSchedulePrivate::intervalToMinutes(AccountSyncSchedule::Interval interval)
{
    switch (interval) {
    case AccountSyncSchedule::NoInterval:
        return 0;
    case AccountSyncSchedule::Every5Minutes:
        return 5;
    case AccountSyncSchedule::Every15Minutes:
        return 15;
    case AccountSyncSchedule::Every30Minutes:
        return 30;
    case AccountSyncSchedule::EveryHour:
        return 60;
    case AccountSyncSchedule::TwiceDailyInterval:
        return 60 * 12;
    }
    qWarning() << "Unhandled sync interval:" << interval;
    return 60;
}

AccountSyncSchedule::Interval AccountSyncSchedulePrivate::intervalFromMinutes(unsigned int minutes)
{
    // roughly match the AccountSyncSchedule intervals if there is no exact match
    AccountSyncSchedule::Interval interval;
    if (minutes <= 0) {
        interval = AccountSyncSchedule::NoInterval;
    } else if (minutes > 0 && minutes <= 5) {
        interval = AccountSyncSchedule::Every5Minutes;
    } else if (minutes <= 15) {
        interval = AccountSyncSchedule::Every15Minutes;
    } else if (minutes <= 45) {
        interval = AccountSyncSchedule::Every30Minutes;
    } else if (minutes <= 60 * 3) {
        interval = AccountSyncSchedule::EveryHour;
    } else {
        interval = AccountSyncSchedule::TwiceDailyInterval;
    }
    return interval;
}

AccountSyncSchedule *AccountSyncSchedulePrivate::fromButeoSchedule(const Buteo::SyncProfile &profile, QObject *parent)
{
    AccountSyncSchedule *result = new AccountSyncSchedule(parent);
    AccountSyncSchedulePrivate *d = result->d;
    const Buteo::SyncSchedule &source = profile.syncSchedule();

    const AccountSyncSchedule::Days daySet(QFlags<Buteo::SyncSchedule::Day>::Int(source.days()));
    const QTime time = source.time();
    if (source.interval() > 0) {
        if (source.interval() == Sync::SYNC_INTERVAL_MONTHLY) {
            result->setLongIntervalSyncMode(AccountSyncSchedule::MonthLongInterval, time);
        } else if (source.interval() == Sync::SYNC_INTERVAL_FIRST_DAY_OF_MONTH) {
            result->setLongIntervalSyncMode(AccountSyncSchedule::FirstDayOfMonthInterval, time);
        } else if (source.interval() == Sync::SYNC_INTERVAL_LAST_DAY_OF_MONTH) {
            result->setLongIntervalSyncMode(AccountSyncSchedule::LastDayOfMonthInterval, time);
        } else {
            result->setIntervalSyncMode(intervalFromMinutes(source.interval()), daySet);
        }
    } else if (time.isValid()) {
        result->setDailySyncMode(time, daySet);
    }

    if (source.rushEnabled()) {
        QTime peakStart = source.rushBegin();
        if (!peakStart.isValid()) {
            peakStart = QTime(9, 0, 0);
        }
        QTime peakEnd = source.rushEnd();
        if (!peakEnd.isValid()) {
            peakEnd = QTime(17, 0, 0);
        }
        AccountSyncSchedule::Interval interval = intervalFromMinutes(source.rushInterval());
        result->setPeakSchedule(peakStart, peakEnd, interval, source.rushDays());
        d->m_peakEnabled = true;
    } else {
        d->m_peakEnabled = false;
    }

    d->m_enabled = source.scheduleEnabled();
    d->m_externalPeakEnabled = source.syncExternallyDuringRush();
    d->m_modified = false;

    return result;
}

Buteo::SyncSchedule AccountSyncSchedulePrivate::toButeoSchedule(AccountSyncSchedule *source, Buteo::SyncProfile *profile)
{
    if (!source) {
        Buteo::SyncSchedule result;
        result.setScheduleEnabled(false);
        return result;
    }

    AccountSyncSchedulePrivate *d = source->d;
    Buteo::SyncSchedule result;
    const QDateTime lastSync = profile->lastSyncTime();

    result.setScheduleEnabled(d->m_enabled);
    result.setDays(Buteo::SyncSchedule::Days(QFlags<AccountSyncSchedule::Day>::Int(d->m_days)));
    result.setTime(d->m_dailySyncTime);

    switch (d->m_longInterval) {
    case AccountSyncSchedule::MonthLongInterval:
        result.setInterval(Sync::SYNC_INTERVAL_MONTHLY);
        break;
    case AccountSyncSchedule::FirstDayOfMonthInterval:
        result.setInterval(Sync::SYNC_INTERVAL_FIRST_DAY_OF_MONTH);
        break;
    case AccountSyncSchedule::LastDayOfMonthInterval:
        result.setInterval(Sync::SYNC_INTERVAL_LAST_DAY_OF_MONTH);
        break;
    case AccountSyncSchedule::NoLongInterval:
        result.setInterval(intervalToMinutes(d->m_interval));
        break;
    }

    result.setRushEnabled(d->m_peakEnabled);
    result.setSyncExternallyDuringRush(d->m_externalPeakEnabled);
    result.setRushDays(Buteo::SyncSchedule::Days(QFlags<AccountSyncSchedule::Day>::Int(d->m_peakDays)));
    result.setRushTime(d->m_peakStartTime, d->m_peakEndTime);
    result.setRushInterval(intervalToMinutes(d->m_peakInterval));
    result.setScheduleConfiguredTime(QDateTime::currentDateTime());

    return result;
}


AccountSyncSchedule::AccountSyncSchedule(QObject *parent)
    : QObject(parent)
    , d(new AccountSyncSchedulePrivate(this))
{
}

AccountSyncSchedule::~AccountSyncSchedule()
{
    delete d;
}

void AccountSyncSchedule::setEnabled(bool enabled)
{
    if (d->m_enabled != enabled) {
        d->m_enabled = enabled;
        emit enabledChanged();
        d->setModified(true);
    }
}

bool AccountSyncSchedule::enabled() const
{
    return d->m_enabled;
}

void AccountSyncSchedule::setDailySyncMode(const QTime &time, int days)
{
    if (d->m_dailySyncTime != time) {
        d->m_dailySyncTime = time;
        d->setModified(true);
        emit dailySyncTimeChanged();
    }

    if (d->m_interval != AccountSyncSchedule::NoInterval) {
        d->m_interval = AccountSyncSchedule::NoInterval;
        d->setModified(true);
        emit intervalChanged();
    }

    if (d->m_longInterval != AccountSyncSchedule::NoLongInterval) {
        d->m_longInterval = AccountSyncSchedule::NoLongInterval;
        d->setModified(true);
        emit longIntervalChanged();
    }

    d->setDays((AccountSyncSchedule::Days)days);
}

void AccountSyncSchedule::setIntervalSyncMode(Interval interval, int days)
{
    if (d->m_interval != interval) {
        d->m_interval = interval;
        d->setModified(true);
        emit intervalChanged();
    }

    if (d->m_dailySyncTime.isValid()) {
        d->m_dailySyncTime = QTime();
        d->setModified(true);
        emit dailySyncTimeChanged();
    }

    if (d->m_longInterval != AccountSyncSchedule::NoLongInterval) {
        d->m_longInterval = AccountSyncSchedule::NoLongInterval;
        d->setModified(true);
        emit longIntervalChanged();
    }

    d->setDays((AccountSyncSchedule::Days)days);
}

void AccountSyncSchedule::setLongIntervalSyncMode(LongInterval interval, const QTime &time)
{
    if (d->m_longInterval != interval) {
        d->m_longInterval = interval;
        d->setModified(true);
        emit longIntervalChanged();
    }

    if (time != d->m_dailySyncTime) {
        d->m_dailySyncTime = time;
        d->setModified(true);
        emit dailySyncTimeChanged();
    }

    if (d->m_interval != AccountSyncSchedule::NoInterval) {
        d->m_interval = AccountSyncSchedule::NoInterval;
        emit intervalChanged();
    }

    d->setDays((AccountSyncSchedule::Days)0);
}

void AccountSyncSchedule::setPeakSchedule(const QTime &peakStart,
                                          const QTime &peakEnd,
                                          Interval peakInterval,
                                          int peakDays)
{
    if (d->m_peakStartTime != peakStart) {
        d->m_peakStartTime = peakStart;
        emit peakStartTimeChanged();
        d->setModified(true);
    }
    if (d->m_peakEndTime != peakEnd) {
        d->m_peakEndTime = peakEnd;
        emit peakEndTimeChanged();
        d->setModified(true);
    }
    if (d->m_peakInterval != peakInterval) {
        d->m_peakInterval = peakInterval;
        emit peakIntervalChanged();
        d->setModified(true);
    }
    const AccountSyncSchedule::Days days = AccountSyncSchedule::Days::fromInt(peakDays);
    if (d->m_peakDays != days) {
        d->m_peakDays = days;
        emit peakDaysChanged();
        d->setModified(true);
    }
}

void AccountSyncSchedule::setDefaultPeakSchedule()
{
    setPeakSchedule(QTime(9, 0, 0),
                    QTime(17, 0, 0),
                    Every15Minutes,
                    weekdays());
}

void AccountSyncSchedule::setPeakScheduleEnabled(bool enable)
{
    if (d->m_peakEnabled != enable) {
        d->m_peakEnabled = enable;
        emit peakScheduleEnabledChanged();
        d->setModified(true);
    }
}

bool AccountSyncSchedule::peakScheduleEnabled() const
{
    return d->m_peakEnabled;
}

void AccountSyncSchedule::setSyncExternallyDuringPeak(bool enable)
{
    if (d->m_externalPeakEnabled != enable) {
        d->m_externalPeakEnabled = enable;
        emit syncExternallyDuringPeakChanged();
        d->setModified(true);
    }
}

bool AccountSyncSchedule::syncExternallyDuringPeak() const
{
    return d->m_externalPeakEnabled;
}

bool AccountSyncSchedule::modified() const
{
    return d->m_modified;
}

int AccountSyncSchedule::days() const
{
    return d->m_days;
}

QTime AccountSyncSchedule::dailySyncTime() const
{
    return d->m_dailySyncTime;
}

AccountSyncSchedule::Interval AccountSyncSchedule::interval() const
{
    return d->m_interval;
}

AccountSyncSchedule::LongInterval AccountSyncSchedule::longInterval() const
{
    return d->m_longInterval;
}

AccountSyncSchedule::Interval AccountSyncSchedule::peakInterval() const
{
    return d->m_peakInterval;
}

QTime AccountSyncSchedule::peakStartTime() const
{
    return d->m_peakStartTime;
}

QTime AccountSyncSchedule::peakEndTime() const
{
    return d->m_peakEndTime;
}

int AccountSyncSchedule::peakDays() const
{
    return d->m_peakDays;
}

AccountSyncSchedule::Days AccountSyncSchedule::everyday()
{
    return Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday;
}

AccountSyncSchedule::Days AccountSyncSchedule::weekdays()
{
    return Monday | Tuesday | Wednesday | Thursday | Friday;
}

AccountSyncSchedule::Days AccountSyncSchedule::weekendDays()
{
    return Saturday | Sunday;
}

//==============================================

AccountSyncOptionsPrivate::AccountSyncOptionsPrivate(AccountSyncOptions *parent)
    : q(parent)
    , m_schedule(0)
    , m_pastSyncPeriod(DefaultPastSyncPeriod)
    , m_direction(DefaultDirection)
    , m_allowedConnectionTypes(0)
    , m_modified(false)
    , m_autoSync(DefaultAutomaticSync)
    , m_syncExternallyEnabled(false)
{
}

AccountSyncOptions *AccountSyncOptionsPrivate::fromButeoProfile(const Buteo::SyncProfile &source, QObject *parent)
{
    AccountSyncOptions *options = new AccountSyncOptions(parent);
    AccountSyncOptionsPrivate *d = options->d;

    int savedPastPeriod = source.key(Buteo::KEY_SYNC_SINCE_DAYS_PAST).toInt();
    if (savedPastPeriod > 0) {
        d->m_pastSyncPeriod = pastSyncPeriodFromDays((unsigned int)savedPastPeriod);
    } else {
        d->m_pastSyncPeriod = DefaultPastSyncPeriod;
    }
    Buteo::SyncProfile::SyncDirection buteoDirection = source.syncDirection();
    switch (buteoDirection) {
    case Buteo::SyncProfile::SYNC_DIRECTION_TWO_WAY:
        d->m_direction = AccountSyncOptions::TwoWaySync;
        break;
    case Buteo::SyncProfile::SYNC_DIRECTION_FROM_REMOTE:
        d->m_direction = AccountSyncOptions::OneWayToDevice;
        break;
    case Buteo::SyncProfile::SYNC_DIRECTION_TO_REMOTE:
        d->m_direction = AccountSyncOptions::OneWayFromDevice;
        break;
    case Buteo::SyncProfile::SYNC_DIRECTION_UNDEFINED:
        d->m_direction = DefaultDirection;
        break;
    }
    d->m_autoSync = source.boolKey(Buteo::KEY_SYNC_ALWAYS_UP_TO_DATE, DefaultAutomaticSync);
    d->m_syncExternallyEnabled = source.boolKey(Buteo::KEY_SYNC_EXTERNALLY, false);
    d->m_schedule = AccountSyncSchedulePrivate::fromButeoSchedule(source, options);

    int connectionTypes = 0;
    const QList<Sync::InternetConnectionType> connectionTypesList = source.internetConnectionTypes();
    for (Sync::InternetConnectionType connectionType : connectionTypesList) {
        switch (connectionType) {
        case Sync::INTERNET_CONNECTION_UNKNOWN:
            break;
        case Sync::INTERNET_CONNECTION_ETHERNET:
            connectionTypes |= AccountSyncOptions::Ethernet;
            break;
        case Sync::INTERNET_CONNECTION_WLAN:
            connectionTypes |= AccountSyncOptions::Wlan;
            break;
        case Sync::INTERNET_CONNECTION_BLUETOOTH:
            connectionTypes |= AccountSyncOptions::Bluetooth;
            break;
        case Sync::INTERNET_CONNECTION_2G:
        case Sync::INTERNET_CONNECTION_3G:
        case Sync::INTERNET_CONNECTION_4G:
        case Sync::INTERNET_CONNECTION_CDMA2000:
        case Sync::INTERNET_CONNECTION_WCDMA:
        case Sync::INTERNET_CONNECTION_HSPA:
        case Sync::INTERNET_CONNECTION_WIMAX:
        case Sync::INTERNET_CONNECTION_EVDO:
        case Sync::INTERNET_CONNECTION_LTE:
            connectionTypes |= AccountSyncOptions::Cellular;
            break;
        }
    }
    d->m_allowedConnectionTypes = connectionTypes;

    QObject::connect(d->m_schedule, &AccountSyncSchedule::modifiedChanged,
                     options, &AccountSyncOptions::modifiedChanged);

    d->m_modified = false;

    return options;
}

void AccountSyncOptionsPrivate::writeToButeoProfile(AccountSyncOptions *options, Buteo::SyncProfile *profile)
{
    AccountSyncOptionsPrivate *d = options->d;

    profile->setKey(Buteo::KEY_SYNC_SINCE_DAYS_PAST, QString::number(pastSyncPeriodToDays(d->m_pastSyncPeriod)));

    Buteo::SyncProfile::SyncDirection buteoDirection = Buteo::SyncProfile::SYNC_DIRECTION_UNDEFINED;
    switch (d->m_direction) {
    case AccountSyncOptions::OneWayToDevice:
        buteoDirection = Buteo::SyncProfile::SYNC_DIRECTION_FROM_REMOTE;
        break;
    case AccountSyncOptions::OneWayFromDevice:
        buteoDirection = Buteo::SyncProfile::SYNC_DIRECTION_TO_REMOTE;
        break;
    case AccountSyncOptions::TwoWaySync:
        buteoDirection = Buteo::SyncProfile::SYNC_DIRECTION_TWO_WAY;
        break;
    }
    profile->setSyncDirection(buteoDirection);
    profile->setKey(Buteo::KEY_SYNC_ALWAYS_UP_TO_DATE, (d->m_autoSync ? "true" : "false"));
    profile->setKey(Buteo::KEY_SYNC_EXTERNALLY, (d->m_syncExternallyEnabled ? "true" : "false"));

    QList<Sync::InternetConnectionType> connectionTypes;
    if (d->m_allowedConnectionTypes & AccountSyncOptions::Ethernet) {
        connectionTypes << Sync::INTERNET_CONNECTION_ETHERNET;
    }
    if (d->m_allowedConnectionTypes & AccountSyncOptions::Wlan) {
        connectionTypes << Sync::INTERNET_CONNECTION_WLAN;
    }
    if (d->m_allowedConnectionTypes & AccountSyncOptions::Cellular) {
        connectionTypes << Sync::INTERNET_CONNECTION_2G
                        << Sync::INTERNET_CONNECTION_3G
                        << Sync::INTERNET_CONNECTION_4G
                        << Sync::INTERNET_CONNECTION_CDMA2000
                        << Sync::INTERNET_CONNECTION_WCDMA
                        << Sync::INTERNET_CONNECTION_CDMA2000
                        << Sync::INTERNET_CONNECTION_HSPA
                        << Sync::INTERNET_CONNECTION_WIMAX
                        << Sync::INTERNET_CONNECTION_EVDO
                        << Sync::INTERNET_CONNECTION_LTE;
    }
    if (d->m_allowedConnectionTypes & AccountSyncOptions::Bluetooth) {
        connectionTypes << Sync::INTERNET_CONNECTION_BLUETOOTH;
    }
    profile->setInternetConnectionTypes(connectionTypes);

    if (options->schedule()) {
        profile->setSyncSchedule(AccountSyncSchedulePrivate::toButeoSchedule(options->schedule(), profile));
    }
}

unsigned int AccountSyncOptionsPrivate::pastSyncPeriodToDays(AccountSyncOptions::PastSyncPeriod period)
{
    switch (period) {
    case AccountSyncOptions::OneDayAgo:
        return 1;
    case AccountSyncOptions::ThreeDaysAgo:
        return 3;
    case AccountSyncOptions::OneWeekAgo:
        return 7;
    case AccountSyncOptions::TwoWeeksAgo:
        return 14;
    case AccountSyncOptions::OneMonthAgo:
        return 30;  // obviously approximate
    };
    qWarning() << "Unhandled sync period!" << period;
    return 7;
}

AccountSyncOptions::PastSyncPeriod AccountSyncOptionsPrivate::pastSyncPeriodFromDays(unsigned int dayCount)
{
    if (dayCount <= 1) {
        return AccountSyncOptions::OneDayAgo;
    } else if (dayCount <= 3) {
        return AccountSyncOptions::ThreeDaysAgo;
    } else if (dayCount <= 7) {
        return AccountSyncOptions::OneWeekAgo;
    } else if (dayCount <= 14) {
        return AccountSyncOptions::TwoWeeksAgo;
    } else {
        return AccountSyncOptions::OneMonthAgo;
    }
}

void AccountSyncOptionsPrivate::setModified(bool modified)
{
    if (modified != m_modified) {
        m_modified = modified;
        emit q->modifiedChanged();
    }
}


AccountSyncOptions::AccountSyncOptions(QObject *parent)
    : QObject(parent)
    , d(new AccountSyncOptionsPrivate(this))
{
}

AccountSyncOptions::~AccountSyncOptions()
{
    delete d;
}

bool AccountSyncOptions::modified() const
{
    return d->m_modified || (d->m_schedule && d->m_schedule->modified());
}

void AccountSyncOptions::setAutomaticSyncEnabled(bool enabled)
{
    if (d->m_autoSync != enabled) {
        d->m_autoSync = enabled;
        emit automaticSyncEnabledChanged();
        d->setModified(true);
    }
}

bool AccountSyncOptions::automaticSyncEnabled() const
{
    return d->m_autoSync;
}

void AccountSyncOptions::setSyncExternallyEnabled(bool enabled)
{
    if (d->m_syncExternallyEnabled != enabled) {
        d->m_syncExternallyEnabled = enabled;
        emit syncExternallyEnabledChanged();
        d->setModified(true);
    }
}

bool AccountSyncOptions::syncExternallyEnabled() const
{
    return d->m_syncExternallyEnabled;
}

AccountSyncOptions::PastSyncPeriod AccountSyncOptions::pastSyncPeriod() const
{
    return d->m_pastSyncPeriod;
}

void AccountSyncOptions::setPastSyncPeriod(PastSyncPeriod period)
{
    if (d->m_pastSyncPeriod != period) {
        d->m_pastSyncPeriod = period;
        emit pastSyncPeriodChanged();
        d->setModified(true);
    }
}

AccountSyncOptions::Direction AccountSyncOptions::direction() const
{
    return d->m_direction;
}

void AccountSyncOptions::setDirection(Direction direction)
{
    if (d->m_direction != direction) {
        d->m_direction = direction;
        emit directionChanged();
        d->setModified(true);
    }
}

int AccountSyncOptions::allowedConnectionTypes() const
{
    return d->m_allowedConnectionTypes;
}

void AccountSyncOptions::setAllowedConnectionTypes(int allowedConnectionTypes)
{
    if (d->m_allowedConnectionTypes != allowedConnectionTypes) {
        d->m_allowedConnectionTypes = allowedConnectionTypes;
        emit allowedConnectionTypesChanged();
        d->setModified(true);
    }
}

AccountSyncSchedule *AccountSyncOptions::schedule() const
{
    return d->m_schedule;
}

void AccountSyncOptions::setSchedule(AccountSyncSchedule *schedule)
{
    if (d->m_schedule != schedule) {
        d->m_schedule = schedule;
        connect(d->m_schedule, &AccountSyncSchedule::modifiedChanged,
                this, &AccountSyncOptions::modifiedChanged);
        emit scheduleChanged();
        d->setModified(true);
    }
}
