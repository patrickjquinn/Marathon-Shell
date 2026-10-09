// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's ResourcePolicy::ResourceEngine: the part of libresourceqt that
// talks to the resource policy manager. Upstream's engine goes through
// libresource (C, libdbus); this one speaks the same D-Bus protocol with
// QtDBus (see keel/nemo-compat/PROVENANCE.md, "Nemo.Policy"), and grants
// everything at once when no manager is on the system bus (development
// hosts, CI), as Keel's earlier stand-in did. Same interface as upstream's
// resource-engine.h, which resource-set.cpp includes.

#ifndef KEEL_RESOURCE_ENGINE_H
#define KEEL_RESOURCE_ENGINE_H

#include <QHash>
#include <QLoggingCategory>
#include <QObject>
#include <QPointer>
#include <QString>

#include <policy/resource-set.h>

class QDBusMessage;

Q_DECLARE_LOGGING_CATEGORY(lcResourceQt)

namespace ResourcePolicy {

// The manager's bit for a resource type (0 for an unknown type).
quint32 resourceTypeToLibresourceType(ResourceType type);

class ResourceEngine : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(ResourceEngine)

public:
    explicit ResourceEngine(ResourceSet *resourceSet);
    ~ResourceEngine() override;

    bool initialize();

    bool connectToManager();
    bool disconnectFromManager();
    bool isConnectedToManager() const;
    bool isConnectingToManager() const;

    bool acquireResources();
    bool releaseResources();
    bool updateResources();

    bool registerAudioProperties(const QString &audioGroup, quint32 pid, const QString &name,
                                 const QString &value);
    bool registerVideoProperties(quint32 pid);

    quint32 id() const;
    bool toBeDeleted() const;

    // Requests from the manager to this set's client object.
    void handleManagerRequest(const QDBusMessage &message);

signals:
    void resourcesBecameAvailable(quint32 bitmaskOfAvailableResources);
    void resourcesGranted(quint32 bitmaskOfGrantedResources);
    void resourcesDenied();
    void resourcesReleased();
    void resourcesLost(quint32 bitmaskOfGrantedResources);
    void connectedToManager();
    void disconnectedFromManager();
    void errorCallback(quint32 code, const char *message);
    void resourcesReleasedByManager();
    void updateOK(bool);

private:
    // Message types of the protocol (the first argument of every message).
    enum MessageType : qint32 {
        Register = 0,
        Unregister = 1,
        Update = 2,
        Acquire = 3,
        Release = 4,
        Grant = 5,
        Advice = 6,
        Audio = 7,
        Video = 8,
        Status = 9,
    };

    bool send(MessageType type, const QVariantList &payload);
    void deliverLocally(MessageType type, quint32 requestNo);
    void handleStatus(quint32 requestNo, qint32 code, const QString &message);
    void handleGrant(quint32 requestNo, quint32 resources);
    void managerAppeared();
    void managerVanished();
    quint32 allResources() const;
    quint32 optionalResources() const;

    QPointer<ResourceSet> m_set;
    const quint32 m_id;
    quint32 m_requestNo = 0;
    quint32 m_mode;
    QHash<quint32, MessageType> m_pending;
    QByteArray m_errorMessage;
    bool m_connected = false;
    bool m_connecting = false;
    bool m_local = false;
    bool m_registered = false;
    bool m_aboutToBeDeleted = false;
};

} // namespace ResourcePolicy

#endif
