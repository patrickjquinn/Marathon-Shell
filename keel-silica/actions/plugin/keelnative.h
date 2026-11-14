// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// What the app compiled in, found by symbol: the generated manifest
// (keel_actions_manifest, from keel::manifest!() or keel_actions.c) and
// the Rust actions and entities of the `keel` crate
// (keel/actions/rust/keel/src/ffi.rs). Looked up in every loaded object
// (dl_iterate_phdr + dlsym): booster-keel loads apps RTLD_LOCAL, so the
// global scope does not have them.
#ifndef KEEL_ACTIONS_NATIVE_H
#define KEEL_ACTIONS_NATIVE_H

#include <QJsonObject>
#include <QJsonValue>
#include <QSet>
#include <QString>

#include <functional>

namespace KeelNative {

using Done = std::function<void(bool ok, const QJsonValue &value)>;

struct Table
{
    QJsonObject manifest;
    QSet<QString> actions;
    QSet<QString> entities;
};

// The symbols found (once; later calls return the same table).
const Table &table();

// Start a native call. `done` runs on the thread that owns `context`
// (queued) with ok and the result, or !ok and {code, message}. False when
// there is no such native action or entity type.
bool invoke(const QString &action, const QJsonValue &arguments, QObject *context, Done done);
bool getEntity(const QString &type, const QString &id, QObject *context, Done done);
bool findEntities(const QString &type, const QString &query, int limit, QObject *context, Done done);

} // namespace KeelNative

#endif
