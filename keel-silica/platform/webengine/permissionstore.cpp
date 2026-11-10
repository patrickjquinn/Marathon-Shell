// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See permissionstore.h.

#include "permissionstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariantMap>

KeelPermissionStore::KeelPermissionStore()
    : m_path(qEnvironmentVariable("KEEL_WEBVIEW_PERMISSIONS"))
{
    if (m_path.isEmpty())
        m_path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/keel-webview/permissions.json");
    load();
}

void KeelPermissionStore::load()
{
    QFile f(m_path);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonArray array = QJsonDocument::fromJson(f.readAll()).array();
    for (const auto &value : array) {
        const QJsonObject o = value.toObject();
        const QString host = o.value(QStringLiteral("uri")).toString();
        const QString type = o.value(QStringLiteral("type")).toString();
        if (host.isEmpty() || type.isEmpty())
            continue;
        m_entries.append({ host, type, o.value(QStringLiteral("capability")).toInt(), Never });
    }
}

void KeelPermissionStore::save() const
{
    QJsonArray array;
    for (const Entry &e : m_entries) {
        if (e.expireType == Never)
            array.append(QJsonObject::fromVariantMap(toMap(e)));
    }
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    QSaveFile f(m_path);
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(array).toJson(QJsonDocument::Compact));
        f.commit();
    }
}

QVariantMap KeelPermissionStore::toMap(const Entry &entry)
{
    return { { QStringLiteral("uri"), entry.host },
             { QStringLiteral("type"), entry.type },
             { QStringLiteral("capability"), entry.capability },
             { QStringLiteral("expireType"), entry.expireType } };
}

void KeelPermissionStore::add(const QString &host, const QString &type, int capability, int expireType)
{
    if (host.isEmpty() || type.isEmpty())
        return;
    remove(host, type);
    m_entries.append({ host, type, capability, expireType == Session ? Session : Never });
    save();
}

void KeelPermissionStore::remove(const QString &host, const QString &type)
{
    const auto removed = m_entries.removeIf([&](const Entry &e) { return e.host == host && e.type == type; });
    if (removed > 0)
        save();
}

int KeelPermissionStore::capability(const QString &host, const QString &type) const
{
    for (const Entry &e : m_entries) {
        if (e.host == host && e.type == type)
            return e.capability;
    }
    return Unknown;
}

QVariantList KeelPermissionStore::all() const
{
    QVariantList out;
    for (const Entry &e : m_entries)
        out.append(toMap(e));
    return out;
}

QVariantList KeelPermissionStore::allForUri(const QString &host) const
{
    QVariantList out;
    for (const Entry &e : m_entries) {
        if (e.host == host)
            out.append(toMap(e));
    }
    return out;
}
