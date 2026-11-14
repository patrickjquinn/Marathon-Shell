// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The ambience read straight from dconf, for direct mode (ADR-0016), where
// no keel-shell forwards it. Same source and same key format as keel-shell
// (keel/shell/PROTOCOL.md section 5, keel/shell/src/core/ambience.cpp, from
// which the parser is ported): every key under /desktop/jolla/theme/ and
// /desktop/sailfish/silica/, as full dconf paths, so Keel.Ambience maps them
// exactly as it maps keel-shell's AmbienceChanged.
//
// Read at start and again on changes (debounced) through keel::dconf
// (keeldconf.h): libdconf on the phone, which works inside Sailjail's
// sandbox, the `dconf` program on hosts without the library. KEEL_DCONF
// names another dconf program (tests).
#ifndef KEEL_DCONFAMBIENCE_H
#define KEEL_DCONFAMBIENCE_H

#include <QObject>
#include <QTimer>
#include <QVariantMap>


namespace keel {

class DconfAmbience : public QObject
{
    Q_OBJECT
public:
    static constexpr int kDebounceMs = 250;
    static constexpr int kDumpTimeoutMs = 1500;

    explicit DconfAmbience(QObject *parent = nullptr);
    ~DconfAmbience() override;

    // `dconf dump <dir>` text -> { "<dir><relative key>": value }.
    static QVariantMap parseDump(const QString &dir, const QString &dump);
    // One GVariant text value: strings, booleans, integers, doubles (with
    // or without a type prefix); anything else stays text.
    static QVariant parseValue(const QString &text);
    // Keeps the keys of the two ambience directories.
    static QVariantMap ambienceOnly(const QVariantMap &values);

    bool available() const;
    QVariantMap values() const { return m_values; }

    // Synchronous read, bounded by kDumpTimeoutMs.
    void readNow();
    void startWatching();

signals:
    void changed(const QVariantMap &values);

private:
    void refresh();
    void onWatchOutput(const QString &text);

    QVariantMap m_values;
    QObject *m_watch = nullptr;
    QTimer m_debounce;
};

} // namespace keel

#endif // KEEL_DCONFAMBIENCE_H
