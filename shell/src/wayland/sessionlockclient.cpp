#include "sessionlockclient.h"

#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcLock, "marathon.shell.session-lock")

static constexpr int kSessionLockVersion = 1;

SessionLockClient::SessionLockClient(QObject *parent)
    : QWaylandClientExtensionTemplate<SessionLockClient>(kSessionLockVersion) {
    setParent(parent);
    connect(this, &QWaylandClientExtension::activeChanged, this,
            [this]() { qCInfo(lcLock) << "session-lock active:" << isActive(); });
}

SessionLockClient::~SessionLockClient() = default;

void SessionLockClient::setLocked(bool locked) {
    if (locked) {
        if (m_lock)
            return;
        if (!isActive()) {
            qCWarning(lcLock) << "setLocked(true) but extension not active";
            emit serverDeniedLock();
            return;
        }
        m_lock = new ExtSessionLockObject(this, lock());
        connect(m_lock, &ExtSessionLockObject::granted, this,
                &SessionLockClient::serverGrantedLock);
        connect(m_lock, &ExtSessionLockObject::finished, this, [this]() {
            // Server denied or preempted the lock — either way our
            // object is no longer valid. Tell the shell so it can
            // decide whether to retry.
            m_lock = nullptr;
            emit serverDeniedLock();
        });
    } else {
        if (!m_lock)
            return;
        m_lock->unlockAndDestroy();
        m_lock = nullptr;
    }
}

// -- lock object ------------------------------------------------------

ExtSessionLockObject::ExtSessionLockObject(SessionLockClient            *client,
                                           struct ::ext_session_lock_v1 *lock)
    : QObject(client)
    , QtWayland::ext_session_lock_v1(lock)
    , m_client(client) {}

ExtSessionLockObject::~ExtSessionLockObject() {
    if (isInitialized() && !m_unlockedOut) {
        // Protocol contract: if we drop the lock without
        // unlock_and_destroy AFTER it was granted, the compositor
        // keeps the session locked. That's the explicit "crash-locked"
        // behavior phosh and friends rely on — we honor it by simply
        // not calling unlock_and_destroy in the unhappy path.
        destroy();
    }
}

void ExtSessionLockObject::unlockAndDestroy() {
    m_unlockedOut = true;
    unlock_and_destroy();
    // unlock_and_destroy is a destructor request on the server side;
    // the QtWayland-generated wrapper releases our proxy.
    deleteLater();
}

void ExtSessionLockObject::ext_session_lock_v1_locked() {
    qCInfo(lcLock) << "compositor granted lock";
    emit granted();
}

void ExtSessionLockObject::ext_session_lock_v1_finished() {
    qCWarning(lcLock) << "compositor refused or preempted lock";
    emit finished();
    deleteLater();
}
