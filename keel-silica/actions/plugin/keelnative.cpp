// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keelnative.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMetaObject>
#include <QPointer>

#include <dlfcn.h>
#include <link.h>

namespace {

using DoneFn = void (*)(void *ctx, int status, const char *json);
using ManifestFn = const char *(*)();
using InvokeFn = int (*)(const char *, const char *, DoneFn, void *);
using GetFn = int (*)(const char *, const char *, DoneFn, void *);
using FindFn = int (*)(const char *, const char *, unsigned, DoneFn, void *);

struct Symbols
{
    ManifestFn manifest = nullptr;
    ManifestFn list = nullptr;
    InvokeFn invoke = nullptr;
    GetFn get = nullptr;
    FindFn find = nullptr;
};

template <typename T>
void lookup(void *handle, const char *name, T &slot)
{
    if (!slot)
        slot = reinterpret_cast<T>(dlsym(handle, name)); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
}

int visit(struct dl_phdr_info *info, size_t, void *data)
{
    auto *s = static_cast<Symbols *>(data);
    const char *name = info->dlpi_name;
    void *handle = dlopen(name && *name ? name : nullptr, RTLD_LAZY | RTLD_NOLOAD);
    if (!handle)
        return 0;
    lookup(handle, "keel_actions_manifest", s->manifest);
    lookup(handle, "keel_actions_native_list", s->list);
    lookup(handle, "keel_actions_native_invoke", s->invoke);
    lookup(handle, "keel_actions_native_entity_get", s->get);
    lookup(handle, "keel_actions_native_entity_find", s->find);
    // The object stays loaded (it was loaded before), so the pointers stay
    // valid after this reference is dropped.
    dlclose(handle);
    return 0;
}

const Symbols &symbols()
{
    static const Symbols s = [] {
        Symbols found;
        dl_iterate_phdr(visit, &found);
        return found;
    }();
    return s;
}

// One pending native call. Deleted by the completion callback.
struct Pending
{
    QPointer<QObject> context;
    KeelNative::Done done;
};

void complete(void *ctx, int status, const char *json)
{
    auto *pending = static_cast<Pending *>(ctx);
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(json ? json : "null"));
    QJsonValue value = doc.isObject() ? QJsonValue(doc.object()) : doc.isArray() ? QJsonValue(doc.array()) : QJsonValue();
    if (doc.isNull()) {
        // A scalar result: QJsonDocument parses only objects and arrays.
        const QJsonDocument wrapped = QJsonDocument::fromJson(QByteArray("[") + QByteArray(json ? json : "null") + ']');
        value = wrapped.array().at(0);
    }
    const bool ok = status == 0;
    QObject *context = pending->context.data();
    if (!context) {
        delete pending;
        return;
    }
    // Back to the context's thread (async Rust actions answer from a worker).
    QMetaObject::invokeMethod(
        context,
        [pending, ok, value]() {
            pending->done(ok, value);
            delete pending;
        },
        Qt::QueuedConnection);
}

} // namespace

namespace KeelNative {

const Table &table()
{
    static const Table t = [] {
        Table table;
        const Symbols &s = symbols();
        if (s.manifest && s.manifest()) {
            table.manifest = QJsonDocument::fromJson(QByteArray(s.manifest())).object();
            if (table.manifest.isEmpty())
                qWarning("Keel.Actions: keel_actions_manifest() is not a JSON object");
        }
        if (s.list && s.list()) {
            const QJsonObject list = QJsonDocument::fromJson(QByteArray(s.list())).object();
            for (const auto &a : list.value(QLatin1String("actions")).toArray())
                table.actions.insert(a.toString());
            for (const auto &e : list.value(QLatin1String("entities")).toArray())
                table.entities.insert(e.toString());
        }
        return table;
    }();
    return t;
}

bool invoke(const QString &action, const QJsonValue &arguments, QObject *context, Done done)
{
    const Symbols &s = symbols();
    if (!s.invoke || !table().actions.contains(action))
        return false;
    const QByteArray name = action.toUtf8();
    const QByteArray args = QJsonDocument(arguments.toObject()).toJson(QJsonDocument::Compact);
    auto *pending = new Pending{context, std::move(done)};
    if (s.invoke(name.constData(), args.constData(), complete, pending) != 0) {
        delete pending;
        return false;
    }
    return true;
}

bool getEntity(const QString &type, const QString &id, QObject *context, Done done)
{
    const Symbols &s = symbols();
    if (!s.get || !table().entities.contains(type))
        return false;
    auto *pending = new Pending{context, std::move(done)};
    if (s.get(type.toUtf8().constData(), id.toUtf8().constData(), complete, pending) != 0) {
        delete pending;
        return false;
    }
    return true;
}

bool findEntities(const QString &type, const QString &query, int limit, QObject *context, Done done)
{
    const Symbols &s = symbols();
    if (!s.find || !table().entities.contains(type))
        return false;
    auto *pending = new Pending{context, std::move(done)};
    if (s.find(type.toUtf8().constData(), query.toUtf8().constData(), static_cast<unsigned>(limit), complete, pending)
        != 0) {
        delete pending;
        return false;
    }
    return true;
}

} // namespace KeelNative
