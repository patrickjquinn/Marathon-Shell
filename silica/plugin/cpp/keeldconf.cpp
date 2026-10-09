// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

// libdconf's headers (through GIO) use `signals` as a name: include them
// before Qt defines it as a macro.
#ifdef KEEL_HAVE_LIBDCONF
#include <dconf.h>
#endif

#include "keeldconf.h"

#include <QProcess>
#include <QStandardPaths>

#ifdef Q_OS_LINUX
#include <csignal>
#include <sys/prctl.h>
#endif

namespace keel::dconf {

namespace {

QString program()
{
    static const QString p = [] {
        const QString overridden = qEnvironmentVariable("KEEL_DCONF");
        return overridden.isEmpty() ? QStandardPaths::findExecutable(QStringLiteral("dconf")) : overridden;
    }();
    return p;
}

bool forcedProgram()
{
    return qEnvironmentVariableIsSet("KEEL_DCONF");
}

#ifdef KEEL_HAVE_LIBDCONF
DConfClient *client()
{
    // One client per process, made on first use (the main thread for
    // Keel's callers); never freed, as dconf's own tools do.
    static DConfClient *c = dconf_client_new();
    return c;
}

QString printed(GVariant *value)
{
    if (!value)
        return QString();
    gchar *text = g_variant_print(value, FALSE);
    const QString out = QString::fromUtf8(text);
    g_free(text);
    g_variant_unref(value);
    return out;
}

void listInto(const QString &dir, QMap<QString, QString> &out, int depth)
{
    if (depth > 16)
        return;
    gint length = 0;
    gchar **names = dconf_client_list(client(), dir.toUtf8().constData(), &length);
    if (!names)
        return;
    for (gint i = 0; i < length; ++i) {
        const QString path = dir + QString::fromUtf8(names[i]);
        if (path.endsWith(QLatin1Char('/'))) {
            listInto(path, out, depth + 1);
        } else {
            const QString value = printed(dconf_client_read(client(), path.toUtf8().constData()));
            if (!value.isEmpty())
                out.insert(path, value);
        }
    }
    g_strfreev(names);
}
#endif

// A `dconf` child that dies with this process (PR_SET_PDEATHSIG): a Keel
// app ended by a signal no longer leaves `dconf watch` running.
void startProgram(QProcess *p, const QStringList &args)
{
#ifdef Q_OS_LINUX
    p->setChildProcessModifier([] { ::prctl(PR_SET_PDEATHSIG, SIGTERM); });
#endif
    p->start(program(), args);
}

QString runProgram(const QStringList &args, int timeoutMs)
{
    if (program().isEmpty())
        return QString();
    QProcess p;
    startProgram(&p, args);
    if (!p.waitForFinished(timeoutMs) || p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        if (p.state() != QProcess::NotRunning) {
            p.kill();
            p.waitForFinished(500);
        }
        return QString();
    }
    return QString::fromUtf8(p.readAllStandardOutput());
}

} // namespace

bool usesLibrary()
{
#ifdef KEEL_HAVE_LIBDCONF
    return !forcedProgram();
#else
    return false;
#endif
}

bool available()
{
    return usesLibrary() || !program().isEmpty();
}

QString read(const QString &key)
{
#ifdef KEEL_HAVE_LIBDCONF
    if (usesLibrary())
        return printed(dconf_client_read(client(), key.toUtf8().constData()));
#endif
    return runProgram({ QStringLiteral("read"), key }, 1000).trimmed();
}

QMap<QString, QString> dump(const QString &dirIn, int timeoutMs)
{
    QString dir = dirIn;
    if (!dir.endsWith(QLatin1Char('/')))
        dir += QLatin1Char('/');
    QMap<QString, QString> out;
#ifdef KEEL_HAVE_LIBDCONF
    if (usesLibrary()) {
        listInto(dir, out, 0);
        return out;
    }
#endif
    // `dconf dump` prints [section] headers relative to dir and key=value
    // lines below them.
    const QString text = runProgram({ QStringLiteral("dump"), dir }, timeoutMs);
    QString section;
    for (const QString &raw : text.split(QLatin1Char('\n'))) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            section = line.mid(1, line.size() - 2);
            if (section == QLatin1String("/"))
                section.clear();
            else if (!section.endsWith(QLatin1Char('/')))
                section += QLatin1Char('/');
            continue;
        }
        const qsizetype eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        out.insert(dir + section + line.left(eq).trimmed(), line.mid(eq + 1).trimmed());
    }
    return out;
}

struct Watch::Private
{
    QString dir;
    QProcess *process = nullptr;
#ifdef KEEL_HAVE_LIBDCONF
    gulong handler = 0;
#endif
};

#ifdef KEEL_HAVE_LIBDCONF
static void onLibraryChanged(DConfClient *, const gchar *prefix, const gchar *const *changes, const gchar *,
                             gpointer data)
{
    auto *watch = static_cast<Watch *>(data);
    QString text = QString::fromUtf8(prefix);
    for (int i = 0; changes && changes[i]; ++i)
        text += QLatin1Char('\n') + QString::fromUtf8(prefix) + QString::fromUtf8(changes[i]);
    emit watch->changed(text);
}
#endif

Watch::Watch(const QString &dir, QObject *parent)
    : QObject(parent)
    , d(new Private)
{
    d->dir = dir;
#ifdef KEEL_HAVE_LIBDCONF
    if (usesLibrary()) {
        d->handler = g_signal_connect(client(), "changed", G_CALLBACK(onLibraryChanged), this);
        dconf_client_watch_fast(client(), dir.toUtf8().constData());
        m_active = true;
        return;
    }
#endif
    if (program().isEmpty())
        return;
    d->process = new QProcess(this);
    d->process->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    connect(d->process, &QProcess::readyReadStandardOutput, this,
            [this] { emit changed(QString::fromUtf8(d->process->readAllStandardOutput())); });
    startProgram(d->process, { QStringLiteral("watch"), dir });
    m_active = true;
}

Watch::~Watch()
{
#ifdef KEEL_HAVE_LIBDCONF
    if (d->handler) {
        dconf_client_unwatch_fast(client(), d->dir.toUtf8().constData());
        g_signal_handler_disconnect(client(), d->handler);
    }
#endif
    if (d->process && d->process->state() != QProcess::NotRunning) {
        d->process->kill();
        d->process->waitForFinished(500);
    }
    delete d;
}

} // namespace keel::dconf
