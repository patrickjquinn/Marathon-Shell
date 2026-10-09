// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Tracker 3 as a content source: one SPARQL query to the file indexer's
// endpoint over D-Bus, as Sailfish's gallery and media apps use Tracker.
//
// Protocol (Tracker 3 libtracker-sparql, src/libtracker-sparql/
// tracker-endpoint-dbus.c and bus/tracker-bus-cursor.c, LGPL; only the
// public wire format is reimplemented here, no Tracker code is used):
//   service   org.freedesktop.Tracker3.Miner.Files (session bus)
//   object    /org/freedesktop/Tracker3/Endpoint
//   interface org.freedesktop.Tracker3.Endpoint
//   method    Query(s sparql, h output_stream, a{sv} arguments) -> as names
// The endpoint writes every result row into the passed pipe before it
// replies, in host byte order: int32 n_columns, n_columns x int32 value
// types, n_columns x int32 offsets (offset i = position of the NUL ending
// value i), then the values, each NUL-terminated. EOF ends the result.
#ifndef KEEL_PICKERS_TRACKERSOURCE_H
#define KEEL_PICKERS_TRACKERSOURCE_H

#include "contentitem.h"

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>

namespace keel::pickers {

class TrackerSource
{
public:
    static QString service();       // KEEL_PICKERS_TRACKER_SERVICE overrides
    static QString objectPath();    // /org/freedesktop/Tracker3/Endpoint
    static QString interfaceName(); // org.freedesktop.Tracker3.Endpoint

    // Whether the indexer answers on the session bus (it is D-Bus
    // activatable, so a registered or activatable name counts).
    static bool available();

    // The SPARQL query Keel sends for a category (Image, Video, Music,
    // Document; others have no Tracker query).
    static QString queryFor(Category category, int limit);

    // Runs the query for `category` (blocking; call it off the GUI thread).
    // Returns false on any D-Bus or format error.
    static bool fetch(Category category, int limit, QList<ContentItem> *items, QString *error);

    // Runs a query and returns the rows as strings (blocking).
    static bool query(const QString &sparql, QList<QStringList> *rows, QString *error);

    // Decodes the cursor stream described above.
    static bool parseCursor(const QByteArray &data, QList<QStringList> *rows, QString *error);
};

} // namespace keel::pickers

#endif // KEEL_PICKERS_TRACKERSOURCE_H
