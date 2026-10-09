// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "ambience.h"

#include <QProcess>
#include <QRegExp>
#include <QStandardPaths>

#include "logging.h"

namespace keel {

QList<DconfSource> Ambience::defaultSources()
{
    QList<DconfSource> sources;
    DconfSource theme;
    theme.dir = QStringLiteral("/desktop/jolla/theme/");
    theme.envPrefix = QStringLiteral("KEEL_AMBIENCE_");
    sources << theme;
    DconfSource silica;
    silica.dir = QStringLiteral("/desktop/sailfish/silica/");
    silica.envPrefix = QStringLiteral("KEEL_SILICA_");
    sources << silica;
    return sources;
}

static QString unescapeQuoted(const QString &text)
{
    // text includes the surrounding quotes.
    QString out;
    out.reserve(text.size());
    for (int i = 1; i < text.size() - 1; ++i) {
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
                    out += QChar(code);
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

QVariant Ambience::parseValue(const QString &rawText)
{
    QString text = rawText.trimmed();
    if (text.isEmpty())
        return QVariant();

    // Strip an explicit GVariant type annotation: "uint32 5", "int64 -1",
    // "double 1.5", "byte 0x10", "@s 'x'".
    static const QRegExp typed(QStringLiteral(
            "^(?:byte|int16|uint16|int32|uint32|int64|uint64|double|handle|@[a-z]+)\\s+(.*)$"));
    if (typed.indexIn(text) == 0)
        text = typed.cap(1).trimmed();

    const QChar first = text.at(0);
    if ((first == QLatin1Char('\'') || first == QLatin1Char('"'))
            && text.size() >= 2 && text.endsWith(first)) {
        return unescapeQuoted(text);
    }
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
    return text;   // arrays, dicts, tuples: forwarded verbatim
}

QVariantMap Ambience::parseDump(const QString &dirIn, const QString &dump)
{
    QString dir = dirIn;
    if (!dir.endsWith(QLatin1Char('/')))
        dir += QLatin1Char('/');

    QVariantMap values;
    QString section;   // relative path of current [group], "" for [/]
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
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        const QString key = line.left(eq).trimmed();
        const QString value = line.mid(eq + 1);
        values.insert(dir + section + key, parseValue(value));
    }
    return values;
}

QString Ambience::envName(const DconfSource &source, const QString &fullKey)
{
    QString rel = fullKey;
    if (rel.startsWith(source.dir))
        rel = rel.mid(source.dir.size());
    QString out = source.envPrefix;
    for (const QChar c : rel) {
        if (c.isLetterOrNumber() && c.unicode() < 128)
            out += c.toUpper();
        else
            out += QLatin1Char('_');
    }
    return out;
}

void Ambience::applyToEnvironment(const QList<DconfSource> &sources,
                                  const QVariantMap &values,
                                  QProcessEnvironment *env)
{
    QStringList forwarded;
    for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
        for (const DconfSource &source : sources) {
            if (!it.key().startsWith(source.dir))
                continue;
            QString text;
            if (it.value().type() == QVariant::Bool)
                text = it.value().toBool() ? QStringLiteral("true") : QStringLiteral("false");
            else
                text = it.value().toString();
            env->insert(envName(source, it.key()), text);
            forwarded << it.key();
            break;
        }
    }
    env->insert(QStringLiteral("KEEL_AMBIENCE_KEYS"), forwarded.join(QLatin1Char(':')));
}

AmbienceMonitor::AmbienceMonitor(const QList<DconfSource> &sources, QObject *parent)
    : QObject(parent)
    , m_sources(sources)
    , m_dconf(QStringLiteral("dconf"))
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(kDebounceMs);
    connect(&m_debounce, &QTimer::timeout, this, &AmbienceMonitor::refreshAsync);
}

AmbienceMonitor::~AmbienceMonitor()
{
    // Kill everything first, then reap: SIGKILL ends the processes at once,
    // so the waits are short and do not add up.
    QList<QProcess *> all = m_watchers;
    all += m_dumps;
    for (QProcess *p : all) {
        p->disconnect(this);
        p->kill();
    }
    for (QProcess *p : all)
        p->waitForFinished(kDumpTimeoutMs);
}

bool AmbienceMonitor::haveDconf() const
{
    return m_dconf.contains(QLatin1Char('/')) || !QStandardPaths::findExecutable(m_dconf).isEmpty();
}

QVariantMap AmbienceMonitor::readAll() const
{
    QVariantMap all;
    if (!haveDconf())
        return all;
    for (const DconfSource &source : m_sources) {
        QProcess p;
        p.start(m_dconf, QStringList() << QStringLiteral("dump") << source.dir);
        if (!p.waitForFinished(kDumpTimeoutMs)) {
            p.kill();
            p.waitForFinished(kDumpTimeoutMs);
            qCWarning(lcKeelShell) << "dconf dump timed out for" << source.dir;
            continue;
        }
        const QVariantMap part = Ambience::parseDump(source.dir,
                                                     QString::fromUtf8(p.readAllStandardOutput()));
        for (auto it = part.constBegin(); it != part.constEnd(); ++it)
            all.insert(it.key(), it.value());
    }
    return all;
}

void AmbienceMonitor::refreshNow()
{
    m_values = readAll();
}

void AmbienceMonitor::refreshAsync()
{
    if (m_dumpsLeft > 0) {
        // A change arrived while dumping: read again once this round ends.
        m_refreshAgain = true;
        return;
    }
    if (!haveDconf() || m_sources.isEmpty())
        return;
    m_next.clear();
    m_dumpsLeft = m_sources.size();
    for (int i = 0; i < m_sources.size(); ++i) {
        auto *p = new QProcess(this);
        m_dumps << p;
        connect(p, static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
                this, [this, p, i](int code, QProcess::ExitStatus status) {
            onDumpDone(p, i, status == QProcess::NormalExit && code == 0);
        });
        connect(p, &QProcess::errorOccurred, this, [this, p, i](QProcess::ProcessError error) {
            // finished() follows every error except a failed start.
            if (error == QProcess::FailedToStart)
                onDumpDone(p, i, false);
        });
        QTimer::singleShot(kDumpTimeoutMs, p, [p]() {
            if (p->state() == QProcess::NotRunning)
                return;
            qCWarning(lcKeelShell) << "dconf dump timed out; keeping the previous values";
            p->kill();
        });
        p->start(m_dconf, QStringList() << QStringLiteral("dump") << m_sources.at(i).dir);
    }
}

void AmbienceMonitor::onDumpDone(QProcess *process, int sourceIndex, bool ok)
{
    if (!m_dumps.removeOne(process))
        return;   // already handled
    process->deleteLater();
    const DconfSource &source = m_sources.at(sourceIndex);
    if (ok) {
        const QVariantMap part = Ambience::parseDump(
                source.dir, QString::fromUtf8(process->readAllStandardOutput()));
        for (auto it = part.constBegin(); it != part.constEnd(); ++it)
            m_next.insert(it.key(), it.value());
    } else {
        // Keep this directory's previous values rather than dropping them.
        for (auto it = m_values.constBegin(); it != m_values.constEnd(); ++it) {
            if (it.key().startsWith(source.dir))
                m_next.insert(it.key(), it.value());
        }
    }
    if (--m_dumpsLeft > 0)
        return;
    if (m_next != m_values) {
        m_values = m_next;
        emit changed(m_values);
    }
    m_next.clear();
    if (m_refreshAgain) {
        m_refreshAgain = false;
        refreshAsync();
    }
}

void AmbienceMonitor::startWatching()
{
    if (!haveDconf()) {
        qCWarning(lcKeelShell) << "no dconf executable; ambience changes will not be forwarded";
        return;
    }
    for (const DconfSource &source : m_sources) {
        auto *p = new QProcess(this);
        connect(p, &QProcess::readyReadStandardOutput, this, &AmbienceMonitor::onWatchOutput);
        p->start(m_dconf, QStringList() << QStringLiteral("watch") << source.dir);
        m_watchers << p;
    }
}

void AmbienceMonitor::onWatchOutput()
{
    auto *p = qobject_cast<QProcess *>(sender());
    if (p)
        p->readAllStandardOutput();
    m_debounce.start();
}

} // namespace keel
