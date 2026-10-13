// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "format.h"
#include "keeldconf.h"

#include <QElapsedTimer>
#include <QJSValue>
#include <QLocale>
#include <QRegularExpression>

namespace keel::clock {

Hours parse(const QString &text)
{
    // GVariant text: '24' (a string), or a bare number.
    QString value = text.trimmed();
    if (value.size() >= 2 && (value.startsWith(QLatin1Char('\'')) || value.startsWith(QLatin1Char('"'))))
        value = value.mid(1, value.size() - 2);
    if (value == QLatin1String("24"))
        return Hours::TwentyFour;
    if (value == QLatin1String("12"))
        return Hours::Twelve;
    return Hours::Locale;
}

Hours setting()
{
    static const QString key = QStringLiteral("/sailfish/i18n/lc_timeformat24h");
    // libdconf reads the mapped database (cheap; a change in Settings shows
    // at once). Through the `dconf` program (hosts without the library) the
    // value is kept for a few seconds; with KEEL_DCONF (tests) it is read
    // every time.
    if (dconf::usesLibrary() || qEnvironmentVariableIsSet("KEEL_DCONF"))
        return parse(dconf::read(key));
    static QElapsedTimer age;
    static Hours cached = Hours::Locale;
    if (!age.isValid() || age.hasExpired(5000)) {
        cached = dconf::available() ? parse(dconf::read(key)) : Hours::Locale;
        age.start();
    }
    return cached;
}

bool twentyFourHours(const QLocale &locale)
{
    switch (setting()) {
    case Hours::TwentyFour:
        return true;
    case Hours::Twelve:
        return false;
    case Hours::Locale:
        break;
    }
    // A 12-hour locale format has "h" and an AM/PM marker ("h:mm AP").
    const QString f = locale.timeFormat(QLocale::ShortFormat);
    return !(f.contains(QLatin1String("ap"), Qt::CaseInsensitive) && f.contains(QLatin1Char('h')));
}

QString adjust(const QString &format, Hours hours)
{
    if (hours == Hours::Locale)
        return format;
    // Only the unquoted parts are format ('klo' and the like stay as they
    // are). The AM/PM marker, when dropped, leaves a NUL that is removed
    // with the spaces around it below.
    QString out;
    bool quoted = false;
    bool sawHour = false;
    bool sawAmPm = false;
    for (qsizetype i = 0; i < format.size(); ++i) {
        const QChar ch = format.at(i);
        if (ch == QLatin1Char('\'')) {
            quoted = !quoted;
            out += ch;
        } else if (quoted) {
            out += ch;
        } else if (ch == QLatin1Char('h') || ch == QLatin1Char('H')) {
            const qsizetype start = i;
            while (i + 1 < format.size() && format.at(i + 1) == ch)
                ++i;
            sawHour = true;
            // The locale's own hour field when it is already on that clock
            // ("H.mm" stays "H.mm"); else "HH" or "h".
            const bool upper = ch == QLatin1Char('H');
            if (upper == (hours == Hours::TwentyFour))
                out += format.mid(start, i - start + 1);
            else
                out += hours == Hours::TwentyFour ? QStringLiteral("HH") : QStringLiteral("h");
        } else if ((ch == QLatin1Char('a') || ch == QLatin1Char('A')) && i + 1 < format.size()
                   && format.at(i + 1).toLower() == QLatin1Char('p')) {
            sawAmPm = true;
            out += hours == Hours::Twelve ? format.mid(i, 2) : QString(QChar(0));
            ++i;
        } else {
            out += ch;
        }
    }
    if (!sawHour)
        return format;
    if (hours == Hours::TwentyFour && sawAmPm) {
        static const QRegularExpression marker(QStringLiteral("\\s*\\x{0}\\s*"));
        // "h:mm AP" -> "HH:mm", "AP h:mm" -> "HH:mm", "d.M. h:mm AP" -> "d.M. HH:mm"
        out.replace(marker, QStringLiteral(" "));
        out = out.trimmed();
    }
    if (hours == Hours::Twelve && !sawAmPm)
        out += QStringLiteral(" AP");
    return out;
}

} // namespace keel::clock

namespace {

// The locale's formats for `type` on the clock the phone's setting asks for.
QString timeFormat(const QLocale &locale, QLocale::FormatType type)
{
    return keel::clock::adjust(locale.timeFormat(type), keel::clock::setting());
}

QString dateTimeFormat(const QLocale &locale, QLocale::FormatType type)
{
    return keel::clock::adjust(locale.dateTimeFormat(type), keel::clock::setting());
}

QDateTime toDateTime(const QVariant &value)
{
    QVariant v = value;
    if (v.userType() == qMetaTypeId<QJSValue>())
        v = v.value<QJSValue>().toVariant();
    if (v.typeId() == QMetaType::QDateTime)
        return v.toDateTime();
    if (v.typeId() == QMetaType::QDate)
        return v.toDate().startOfDay();
    if (v.typeId() == QMetaType::QString) {
        QDateTime dt = QDateTime::fromString(v.toString(), Qt::ISODateWithMs);
        if (!dt.isValid())
            dt = QDateTime::fromString(v.toString(), Qt::ISODate);
        if (!dt.isValid())
            dt = QDateTime::fromString(v.toString(), Qt::RFC2822Date);
        return dt;
    }
    if (v.canConvert<double>() && v.typeId() != QMetaType::Bool)
        return QDateTime::fromMSecsSinceEpoch(static_cast<qint64>(v.toDouble()));
    return QDateTime();
}

// The plural strings are tr(..., n) calls with "%n ...(s)" sources, so
// lupdate extracts them and translations supply every plural form of the
// language. Without a translation Qt returns the source with "(s)" left in;
// this turns that into the English singular or plural.
QString englishPlural(QString text, qint64 n)
{
    text.replace(QLatin1String("(s)"), n == 1 ? QString() : QStringLiteral("s"));
    return text;
}

} // namespace

QDateTime KeelFormatter::now() const
{
    return m_now.isValid() ? m_now : QDateTime::currentDateTime();
}

QString KeelFormatter::formatDate(const QVariant &dateTime, int formatType) const
{
    const QDateTime dt = toDateTime(dateTime).toLocalTime();
    if (!dt.isValid())
        return QString();
    const QLocale locale;
    const QDateTime current = now().toLocalTime();
    const qint64 days = dt.date().daysTo(current.date());

    switch (formatType) {
    case Timepoint:
        return locale.toString(dt, dateTimeFormat(locale, QLocale::ShortFormat));
    case TimepointRelative:
        if (days == 0)
            return locale.toString(dt.time(), timeFormat(locale, QLocale::ShortFormat));
        if (days == 1)
            return tr("Yesterday");
        if (days > 1 && days < 7)
            return locale.standaloneDayName(dt.date().dayOfWeek(), QLocale::LongFormat);
        return locale.toString(dt.date(), QLocale::ShortFormat);
    case TimepointRelativeCurrentDay:
        if (days == 0)
            return locale.toString(dt.time(), timeFormat(locale, QLocale::ShortFormat));
        return locale.toString(dt.date(), QLocale::ShortFormat);
    case TimepointSectionRelative:
        if (days == 0)
            return tr("Today");
        if (days == 1)
            return tr("Yesterday");
        if (days > 1 && days < 7)
            return locale.standaloneDayName(dt.date().dayOfWeek(), QLocale::LongFormat);
        return locale.toString(dt.date(), QLocale::LongFormat);
    case WeekdayNameStandalone:
        return locale.standaloneDayName(dt.date().dayOfWeek(), QLocale::LongFormat);
    case DurationElapsed: {
        const qint64 secs = dt.secsTo(current);
        if (secs < 60)
            return tr("Just now");
        if (secs < 3600)
            return englishPlural(tr("%n minute(s) ago", nullptr, static_cast<int>(secs / 60)), secs / 60);
        if (secs < static_cast<qint64>(24) * 3600)
            return englishPlural(tr("%n hour(s) ago", nullptr, static_cast<int>(secs / 3600)), secs / 3600);
        if (days < 7)
            return englishPlural(tr("%n day(s) ago", nullptr, static_cast<int>(qMax<qint64>(1, days))), qMax<qint64>(1, days));
        return locale.toString(dt.date(), QLocale::ShortFormat);
    }
    case TimeValueTwelveHours:
        return locale.toString(dt.time(), QStringLiteral("h:mm AP"));
    case TimeValueTwentyFourHours:
        return locale.toString(dt.time(), QStringLiteral("HH:mm"));
    case TimeValue:
        return locale.toString(dt.time(), timeFormat(locale, QLocale::ShortFormat));
    case DurationShort:
    case DurationLong:
        return formatDuration(static_cast<int>(dt.secsTo(current)), formatType);
    case DateLong:
        return locale.toString(dt.date(), QLocale::LongFormat);
    case MonthNameStandalone:
        return locale.standaloneMonthName(dt.date().month(), QLocale::LongFormat);
    case MonthNameStandaloneShort:
        return locale.standaloneMonthName(dt.date().month(), QLocale::ShortFormat);
    default:
        return locale.toString(dt, dateTimeFormat(locale, QLocale::ShortFormat));
    }
}

QString KeelFormatter::formatArticle(int articleType) const
{
    const QLocale locale;
    return articleType == PostMeridiemIndicator ? locale.pmText() : locale.amText();
}

QString KeelFormatter::formatDuration(int seconds, int formatType) const
{
    const bool negative = seconds < 0;
    const int total = negative ? -seconds : seconds;
    const int h = total / 3600;
    const int m = (total % 3600) / 60;
    const int s = total % 60;
    QString out;
    if (formatType == DurationLong) {
        QStringList parts;
        if (h > 0)
            parts << englishPlural(tr("%n hour(s)", nullptr, (h)), h);
        if (m > 0)
            parts << englishPlural(tr("%n minute(s)", nullptr, (m)), m);
        if (s > 0 || parts.isEmpty())
            parts << englishPlural(tr("%n second(s)", nullptr, (s)), s);
        out = parts.join(QLatin1Char(' '));
    } else if (h > 0) {
        out = QStringLiteral("%1:%2:%3").arg(h).arg(m, 2, 10, QLatin1Char('0')).arg(s, 2, 10, QLatin1Char('0'));
    } else {
        out = QStringLiteral("%1:%2").arg(m).arg(s, 2, 10, QLatin1Char('0'));
    }
    return negative ? QStringLiteral("-") + out : out;
}

QString KeelFormatter::formatFileSize(qlonglong bytes) const
{
    const QLocale locale;
    if (bytes < 1024)
        return tr("%1 B").arg(locale.toString(bytes));
    // Powers of 1024 with the matching traditional symbols (KB, MB, ...),
    // localised by QLocale; one decimal below 10 units.
    auto value = static_cast<double>(bytes);
    while (value >= 1024.0)
        value /= 1024.0;
    const int precision = value < 10.0 ? 1 : 0;
    return locale.formattedDataSize(bytes, precision, QLocale::DataSizeTraditionalFormat);
}

QString KeelFormatter::formatText(const QString &input, int formatType) const
{
    // Decompose and drop what is not 7-bit ASCII (accents, mostly).
    QString ascii;
    const QString decomposed = input.normalized(QString::NormalizationForm_KD);
    for (const QChar c : decomposed) {
        if (c.unicode() < 128)
            ascii.append(c);
    }
    if (formatType == PortableFilename) {
        static const QRegularExpression notPortable(QStringLiteral("[^A-Za-z0-9._-]"));
        ascii.replace(notPortable, QStringLiteral("_"));
    }
    return ascii;
}
