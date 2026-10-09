// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// dconf access for Keel's own plugins: through libdconf (the client library
// every Sailfish OS image has), and only where it is missing (hosts built
// without dconf-devel) through the `dconf` program.
//
// The library matters on the phone: Sailjail runs apps with private-bin, so
// a sandboxed app's /usr/bin has no `dconf` program, while dconf's
// databases (~/.config/dconf/user, /etc/dconf) are readable there. Reading
// through the program left sandboxed Keel apps without the ambience (no
// theme pixel ratio, so no theme icons) and without the display's cutouts.
//
// Values come back as GVariant text (g_variant_print without type
// annotations), the format `dconf dump` and `dconf read` print, so callers
// parse them the same way whichever path read them.
#ifndef KEEL_DCONF_H
#define KEEL_DCONF_H

#include <QMap>
#include <QObject>
#include <QString>
#include <QStringList>

namespace keel::dconf {

// Whether dconf can be read at all (library built in, or the program found;
// KEEL_DCONF names another program, for tests, and forces the program).
bool available();
// True when the library is used (else the program).
bool usesLibrary();
// One key's value as text; empty if unset or unreadable.
QString read(const QString &key);
// Every key below `dir` (which ends with '/'), recursively, as full paths,
// with its value as text. Bounded: a program run is given timeoutMs.
QMap<QString, QString> dump(const QString &dir, int timeoutMs = 1500);

// Change notification for keys below a directory: libdconf's watch (needs
// the GLib main loop Qt runs on, its default event dispatcher on Linux), or
// a `dconf watch` process tied to this one's lifetime.
class Watch : public QObject
{
    Q_OBJECT
public:
    explicit Watch(const QString &dir, QObject *parent = nullptr);
    ~Watch() override;
    bool active() const { return m_active; }

signals:
    // Something below the directory changed; `text` names the keys or
    // directories (as `dconf watch` prints them, or the library's prefix).
    void changed(const QString &text);

private:
    struct Private;
    Private *d;
    bool m_active = false;
};

} // namespace keel::dconf

#endif // KEEL_DCONF_H
