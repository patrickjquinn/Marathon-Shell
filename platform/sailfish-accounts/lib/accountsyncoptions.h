/*
 * SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ACCOUNTSYNCOPTIONS_H
#define ACCOUNTSYNCOPTIONS_H

#include <QObject>
#include <QTime>

class AccountSyncSchedulePrivate;
class AccountSyncOptionsPrivate;

class Q_DECL_EXPORT AccountSyncSchedule : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int days READ days NOTIFY daysChanged)
    Q_PROPERTY(QTime dailySyncTime READ dailySyncTime NOTIFY dailySyncTimeChanged)
    Q_PROPERTY(Interval interval READ interval NOTIFY intervalChanged)
    Q_PROPERTY(LongInterval longInterval READ longInterval NOTIFY longIntervalChanged)
    Q_PROPERTY(bool peakScheduleEnabled READ peakScheduleEnabled WRITE setPeakScheduleEnabled NOTIFY peakScheduleEnabledChanged)
    Q_PROPERTY(bool syncExternallyDuringPeak READ syncExternallyDuringPeak WRITE setSyncExternallyDuringPeak NOTIFY syncExternallyDuringPeakChanged)
    Q_PROPERTY(QTime peakStartTime READ peakStartTime NOTIFY peakStartTimeChanged)
    Q_PROPERTY(QTime peakEndTime READ peakEndTime NOTIFY peakEndTimeChanged)
    Q_PROPERTY(Interval peakInterval READ peakInterval NOTIFY peakIntervalChanged)
    Q_PROPERTY(int peakDays READ peakDays NOTIFY peakDaysChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged)

public:
    enum Interval {
        Every15Minutes,
        Every30Minutes,
        EveryHour,
        TwiceDailyInterval,
        Every5Minutes,
        NoInterval = 100
    };
    Q_ENUM(Interval)

    enum LongInterval {
        MonthLongInterval,
        FirstDayOfMonthInterval,
        LastDayOfMonthInterval,
        NoLongInterval = 100
    };
    Q_ENUM(LongInterval)

    enum Day {
        Monday = 0x01,
        Tuesday = 0x02,
        Wednesday = 0x04,
        Thursday = 0x08,
        Friday = 0x10,
        Saturday = 0x20,
        Sunday = 0x40,
        WeekDays = Monday | Tuesday | Wednesday | Thursday | Friday,
        WeekendDays = Saturday | Sunday,
        EveryDay = WeekDays | WeekendDays,
    };
    Q_ENUM(Day)
    Q_DECLARE_FLAGS(Days, Day)

    AccountSyncSchedule(QObject *parent = 0);
    ~AccountSyncSchedule();

    void setEnabled(bool enabled);
    bool enabled() const;

    Q_INVOKABLE void setDailySyncMode(const QTime &time, int days = everyday());
    Q_INVOKABLE void setIntervalSyncMode(Interval interval, int days = everyday());
    Q_INVOKABLE void setLongIntervalSyncMode(LongInterval interval, const QTime &time);

    void setPeakScheduleEnabled(bool enable);
    bool peakScheduleEnabled() const;
    void setSyncExternallyDuringPeak(bool enable);
    bool syncExternallyDuringPeak() const;

    Q_INVOKABLE void setPeakSchedule(const QTime &peakStart,
                                     const QTime &peakEnd,
                                     Interval peakInterval,
                                     int peakDays);
    Q_INVOKABLE void setDefaultPeakSchedule();

    bool modified() const;

    int days() const;
    Interval interval() const;
    QTime dailySyncTime() const;
    LongInterval longInterval() const;

    int peakDays() const;
    Interval peakInterval() const;
    QTime peakStartTime() const;
    QTime peakEndTime() const;

    static Days everyday();
    static Days weekdays();
    static Days weekendDays();

Q_SIGNALS:
    void enabledChanged();
    void daysChanged();
    void intervalChanged();
    void longIntervalChanged();
    void peakIntervalChanged();
    void dailySyncTimeChanged();
    void peakScheduleEnabledChanged();
    void syncExternallyDuringPeakChanged();
    void peakStartTimeChanged();
    void peakEndTimeChanged();
    void peakDaysChanged();
    void modifiedChanged();

private:
    friend class AccountSyncSchedulePrivate;
    AccountSyncSchedulePrivate *d;
};
Q_DECLARE_OPERATORS_FOR_FLAGS(AccountSyncSchedule::Days);


class Q_DECL_EXPORT AccountSyncOptions : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool automaticSyncEnabled READ automaticSyncEnabled WRITE setAutomaticSyncEnabled NOTIFY automaticSyncEnabledChanged)
    Q_PROPERTY(bool syncExternallyEnabled READ syncExternallyEnabled WRITE setSyncExternallyEnabled NOTIFY syncExternallyEnabledChanged)
    Q_PROPERTY(PastSyncPeriod pastSyncPeriod READ pastSyncPeriod WRITE setPastSyncPeriod NOTIFY pastSyncPeriodChanged)
    Q_PROPERTY(Direction direction READ direction WRITE setDirection NOTIFY directionChanged)
    Q_PROPERTY(int allowedConnectionTypes READ allowedConnectionTypes WRITE setAllowedConnectionTypes NOTIFY allowedConnectionTypesChanged)
    Q_PROPERTY(AccountSyncSchedule *schedule READ schedule WRITE setSchedule NOTIFY scheduleChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged)
    Q_ENUMS(PastSyncPeriod)
    Q_ENUMS(Direction)
    Q_ENUMS(NetworkConnection)
public:
    enum PastSyncPeriod {
        OneDayAgo,
        ThreeDaysAgo,
        OneWeekAgo,
        TwoWeeksAgo,
        OneMonthAgo
    };

    enum Direction {
        OneWayToDevice,
        OneWayFromDevice,
        TwoWaySync
    };

    enum NetworkConnection {
        Ethernet = 0x01,
        Wlan = 0x02,
        Cellular = 0x04,
        Bluetooth = 0x08
    };
    Q_DECLARE_FLAGS(NetworkConnections, NetworkConnection)

    AccountSyncOptions(QObject *parent = 0);
    ~AccountSyncOptions();

    bool modified() const;

    void setAutomaticSyncEnabled(bool enabled);
    bool automaticSyncEnabled() const;

    void setSyncExternallyEnabled(bool enabled);
    bool syncExternallyEnabled() const;

    PastSyncPeriod pastSyncPeriod() const;
    void setPastSyncPeriod(PastSyncPeriod period);

    Direction direction() const;
    void setDirection(Direction direction);

    int allowedConnectionTypes() const;
    void setAllowedConnectionTypes(int allowedConnectionTypes);

    AccountSyncSchedule *schedule() const;
    void setSchedule(AccountSyncSchedule *schedule);

Q_SIGNALS:
    void automaticSyncEnabledChanged();
    void syncExternallyEnabledChanged();
    void pastSyncPeriodChanged();
    void directionChanged();
    void allowedConnectionTypesChanged();
    void scheduleChanged();
    void modifiedChanged();

private:
    friend class AccountSyncOptionsPrivate;
    AccountSyncOptionsPrivate *d;
};
Q_DECLARE_OPERATORS_FOR_FLAGS(AccountSyncOptions::NetworkConnections);

#endif
