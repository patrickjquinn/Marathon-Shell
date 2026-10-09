// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Format (singleton) and Formatter (enum holder). Names, enum values and
// method signatures from the public Silica API listing (plugins.qmltypes as
// posted to the SailfishOS devel mailing list, 2014-02-24: FormatType,
// ArticleType, TextFormatType; formatDate, formatArticle, formatDuration,
// formatFileSize, formatText). The wording and layout of the strings are
// Keel's own, built on QLocale; clean-room.
#ifndef KEEL_FORMAT_H
#define KEEL_FORMAT_H

#include <QDateTime>
#include <QObject>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class KeelFormatter : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Formatter)
    QML_UNCREATABLE("Formatter is an enum holder; use the Format singleton")

public:
    enum FormatType {
        Timepoint = 0,
        TimepointRelative = 1,
        TimepointRelativeCurrentDay = 2,
        TimepointSectionRelative = 3,
        WeekdayNameStandalone = 4,
        DurationElapsed = 5,
        TimeValueTwelveHours = 6,
        TimeValueTwentyFourHours = 7,
        TimeValue = 8,
        DurationShort = 9,
        DurationLong = 10,
        CallTimeRelative = 1,
        // Used by Silica's BSD date pickers (DatePickerDialog, DateGrid,
        // YearMonthMenu), not in the 2014 listing; the values are Keel's
        // own (apps use the names).
        DateLong = 11,
        MonthNameStandalone = 12,
        MonthNameStandaloneShort = 13
    };
    Q_ENUM(FormatType)

    enum ArticleType {
        AnteMeridiemIndicator = 0,
        PostMeridiemIndicator = 1
    };
    Q_ENUM(ArticleType)

    enum TextFormatType {
        Ascii7Bit = 0,
        PortableFilename = 1
    };
    Q_ENUM(TextFormatType)

    using QObject::QObject;

    // dateTime: a JS Date, a QDateTime or an ISO 8601 string.
    Q_INVOKABLE QString formatDate(const QVariant &dateTime, int formatType) const;
    Q_INVOKABLE QString formatArticle(int articleType) const;
    Q_INVOKABLE QString formatDuration(int seconds, int formatType) const;
    Q_INVOKABLE QString formatFileSize(qlonglong bytes) const;
    Q_INVOKABLE QString formatText(const QString &input, int formatType) const;

    // For tests: the "now" relative formats compare against (invalid: the
    // current time).
    Q_INVOKABLE void _setReferenceTime(const QDateTime &now) { m_now = now; }

private:
    QDateTime now() const;
    QDateTime m_now;
};

class KeelFormat : public KeelFormatter
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Format)
    QML_SINGLETON

public:
    using KeelFormatter::KeelFormatter;
};

#endif
