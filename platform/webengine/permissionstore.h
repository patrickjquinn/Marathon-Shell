// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the site permissions Gecko keeps for a Sailfish WebView
// (nsIPermissionManager: host, type such as "geolocation", "camera",
// "microphone", "popup", capability Allow/Deny/Prompt, expiry Never/Session),
// kept for Keel's Qt WebEngine views. Persistent ones in
// <app data>/keel-webview/permissions.json (KEEL_WEBVIEW_PERMISSIONS
// replaces the path), session ones in memory. WebEngine answers Sailfish's
// "embedui:perms" observer requests from it (as Gecko does, for the
// Sailfish.WebView.Controls permission models), and Keel's popup bridge
// answers a page's permission request from it when the user chose
// "don't ask again".

#ifndef KEEL_PERMISSIONSTORE_H
#define KEEL_PERMISSIONSTORE_H

#include <QList>
#include <QString>
#include <QVariantList>

class KeelPermissionStore
{
public:
    enum Capability { Unknown = 0, Allow = 1, Deny = 2, Prompt = 3 };
    enum Expiration { Never = 0, Session = 1 };

    KeelPermissionStore();

    void add(const QString &host, const QString &type, int capability, int expireType);
    void remove(const QString &host, const QString &type);
    int capability(const QString &host, const QString &type) const;
    // Entries as Gecko lists them: uri, type, capability, expireType.
    QVariantList all() const;
    QVariantList allForUri(const QString &host) const;

private:
    struct Entry
    {
        QString host;
        QString type;
        int capability;
        int expireType;
    };
    void load();
    void save() const;
    static QVariantMap toMap(const Entry &entry);

    QString m_path;
    QList<Entry> m_entries;
};

#endif // KEEL_PERMISSIONSTORE_H
