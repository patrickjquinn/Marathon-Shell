// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Parser ported from keel-shell (keel/shell/src/core/ambience.cpp, Qt 5) to
// Qt 6; same behaviour, same tests' expectations.

#include "dconfambience.h"

#include "keeldconf.h"

#include <QLoggingCategory>
#include <QRegularExpression>

Q_LOGGING_CATEGORY(lcKeelDconf, "keel.ambience")

namespace keel {

namespace {

const char *const kRoot = "/desktop/";
const char *const kDirs[] = { "/desktop/jolla/theme/", "/desktop/sailfish/silica/" };

QString unescapeQuoted(const QString &text)
{
    QString out;
    out.reserve(text.size());
    for (qsizetype i = 1; i < text.size() - 1; ++i) {
        const QChar c = text.at(i);
        if (c == QLatin1Char('\\') && i + 1 < text.size() - 1) {
            const QChar n = text.at(++i);
            switch (n.unicode()) {
            case 'n': out += QLatin1Char('\n'); break;
            case 't': out += QLatin1Char('\t'); break;
            case 'r': out += QLatin1Char('\r'); break;
            case 'u': {
                bool ok = false;
                const uint code = text.mid(i + 1, 4).toUInt(&ok, 16);
                if (ok) {
                    out += QChar(static_cast<char16_t>(code));
                    i += 4;
                } else {
                    out += n;
                }
                break;
            }
            default: out += n; break;
            }
        } else {
            out += c;
        }
    }
    return out;
}

} // namespace

DconfAmbience::DconfAmbience(QObject *parent)
    : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(kDebounceMs);
    connect(&m_debounce, &QTimer::timeout, this, &DconfAmbience::refresh);
}

DconfAmbience::~DconfAmbience() = default;

bool DconfAmbience::available() const
{
    return dconf::available();
}

QVariant DconfAmbience::parseValue(const QString &rawText)
{
    QString text = rawText.trimmed();
    if (text.isEmpty())
        return QVariant();
    static const QRegularExpression typed(QStringLiteral(
            "^(?:byte|int16|uint16|int32|uint32|int64|uint64|double|handle|@[a-z]+)\\s+(.*)$"));
    const QRegularExpressionMatch m = typed.match(text);
    if (m.hasMatch())
        text = m.captured(1).trimmed();
    if (text.isEmpty())
        return QVariant();
    const QChar first = text.at(0);
    if ((first == QLatin1Char('\'') || first == QLatin1Char('"')) && text.size() >= 2 && text.endsWith(first))
        return unescapeQuoted(text);
    if (text == QLatin1String("true"))
        return true;
    if (text == QLatin1String("false"))
        return false;
    bool ok = false;
    const qlonglong asInt = text.toLongLong(&ok, 0);
    if (ok)
        return asInt;
    const double asDouble = text.toDouble(&ok);
    if (ok)
        return asDouble;
    return text;
}

QVariantMap DconfAmbience::parseDump(const QString &dirIn, const QString &dump)
{
    QString dir = dirIn;
    if (!dir.endsWith(QLatin1Char('/')))
        dir += QLatin1Char('/');
    QVariantMap values;
    QString section;
    const QStringList lines = dump.split(QLatin1Char('\n'));
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            section = line.mid(1, line.size() - 2);
            if (section == QLatin1String("/"))
                section.clear();
            while (section.startsWith(QLatin1Char('/')))
                section.remove(0, 1);
            if (!section.isEmpty() && !section.endsWith(QLatin1Char('/')))
                section += QLatin1Char('/');
            continue;
        }
        const qsizetype eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        values.insert(dir + section + line.left(eq).trimmed(), parseValue(line.mid(eq + 1)));
    }
    return values;
}

QVariantMap DconfAmbience::ambienceOnly(const QVariantMap &values)
{
    QVariantMap out;
    for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
        for (const char *dir : kDirs) {
            if (it.key().startsWith(QLatin1String(dir))) {
                out.insert(it.key(), it.value());
                break;
            }
        }
    }
    return out;
}

void DconfAmbience::readNow()
{
    if (!available())
        return;
    QVariantMap values;
    for (const char *dir : kDirs) {
        const QMap<QString, QString> texts = dconf::dump(QLatin1String(dir), kDumpTimeoutMs);
        for (auto it = texts.cbegin(); it != texts.cend(); ++it)
            values.insert(it.key(), parseValue(it.value()));
    }
    if (values.isEmpty() && !dconf::usesLibrary())
        qCWarning(lcKeelDconf) << "dconf dump gave no ambience";
    m_values = ambienceOnly(values);
}

void DconfAmbience::startWatching()
{
    if (!available() || m_watch)
        return;
    auto *watch = new dconf::Watch(QLatin1String(kRoot), this);
    connect(watch, &dconf::Watch::changed, this, &DconfAmbience::onWatchOutput);
    m_watch = watch;
}

void DconfAmbience::onWatchOutput(const QString &text)
{
    bool relevant = false;
    for (const char *dir : kDirs)
        relevant = relevant || text.contains(QLatin1String(dir)) || QLatin1String(dir).startsWith(text.section(QLatin1Char('\n'), 0, 0));
    if (relevant)
        m_debounce.start();
}

void DconfAmbience::refresh()
{
    const QVariantMap before = m_values;
    readNow();
    if (m_values != before)
        emit changed(m_values);
}

} // namespace keel
