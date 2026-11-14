// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Ambience forwarding. Sailfish keeps the active ambience in dconf under
// /desktop/jolla/theme/ (Sailfish OS docs, "Ambience > Storage of Settings").
// keel-shell does not hard-code key names: it dumps the configured dconf
// directories with the `dconf` CLI, forwards every key generically, and
// re-dumps when `dconf watch` reports a change. See PROTOCOL.md.

#ifndef KEEL_AMBIENCE_H
#define KEEL_AMBIENCE_H

#include <QObject>
#include <QProcessEnvironment>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

class QProcess;

namespace keel {

struct DconfSource {
    QString dir;          // dconf directory, with leading and trailing '/'
    QString envPrefix;    // e.g. "KEEL_AMBIENCE_"
};

class Ambience
{
public:
    // Default sources: /desktop/jolla/theme/ -> KEEL_AMBIENCE_,
    //                  /desktop/sailfish/silica/ -> KEEL_SILICA_
    static QList<DconfSource> defaultSources();

    // Parses `dconf dump <dir>` output into { "<dir><relative key>": value }.
    // GVariant text values are decoded for strings, booleans, integers and
    // doubles (with or without a type prefix such as "uint32 5"); anything
    // else (arrays, dictionaries) is kept as its GVariant text.
    static QVariantMap parseDump(const QString &dir, const QString &dump);

    // Decodes one GVariant text value.
    static QVariant parseValue(const QString &text);

    // "/desktop/jolla/theme/color/highlight" with prefix KEEL_AMBIENCE_ and
    // dir /desktop/jolla/theme/ -> "KEEL_AMBIENCE_COLOR_HIGHLIGHT".
    static QString envName(const DconfSource &source, const QString &fullKey);

    // Adds one environment variable per key in `values` belonging to a
    // source, plus KEEL_AMBIENCE_KEYS listing the full keys forwarded.
    static void applyToEnvironment(const QList<DconfSource> &sources,
                                   const QVariantMap &values,
                                   QProcessEnvironment *env);
};

// Watches dconf and keeps an up-to-date QVariantMap of all keys.
//
// Only the start-up read (refreshNow) waits for `dconf dump`; it runs before
// keel-shell shows any window. Later reads (refreshAsync, after `dconf
// watch` reports a change and the debounce expires) run the dumps as
// asynchronous processes, so the compositor's GUI thread never blocks on
// dconf.
class AmbienceMonitor : public QObject
{
    Q_OBJECT
public:
    // An ambience switch rewrites many keys in a burst; changes within this
    // window are collapsed into one re-read.
    static constexpr int kDebounceMs = 250;
    // Upper bound for one `dconf dump`; a slower one is killed and that
    // directory keeps its previous values.
    static constexpr int kDumpTimeoutMs = 1500;

    explicit AmbienceMonitor(const QList<DconfSource> &sources, QObject *parent = nullptr);
    ~AmbienceMonitor() override;

    // Synchronous initial read (bounded by kDumpTimeoutMs per directory).
    void refreshNow();
    void startWatching();

    QVariantMap values() const { return m_values; }
    QList<DconfSource> sources() const { return m_sources; }

    void setDconfProgram(const QString &program) { m_dconf = program; }

signals:
    void changed(const QVariantMap &values);

public slots:
    // Re-reads every source without blocking; emits changed() once all
    // dumps have finished, if anything differs.
    void refreshAsync();

private slots:
    void onWatchOutput();

private:
    bool haveDconf() const;
    QVariantMap readAll() const;
    void onDumpDone(QProcess *process, int sourceIndex, bool ok);

    QList<DconfSource> m_sources;
    QVariantMap m_values;
    QString m_dconf;
    QList<QProcess *> m_watchers;
    QTimer m_debounce;

    // The asynchronous refresh in progress.
    QList<QProcess *> m_dumps;
    QVariantMap m_next;
    int m_dumpsLeft = 0;
    bool m_refreshAgain = false;
};

} // namespace keel

#endif // KEEL_AMBIENCE_H
