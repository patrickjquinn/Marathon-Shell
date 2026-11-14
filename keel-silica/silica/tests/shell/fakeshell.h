// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Test double for keel-shell's peer D-Bus server (keel/shell/PROTOCOL.md
// section 4), written from the protocol document. It runs in its own thread
// so that the app side's blocking calls (GetAll at connect) are answered.
#ifndef KEEL_TEST_FAKESHELL_H
#define KEEL_TEST_FAKESHELL_H

#include <QDBusConnection>
#include <QDBusServer>
#include <QMutex>
#include <QObject>
#include <QThread>
#include <QVariantMap>

class FakeShellObject : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.keel.Shell1")
    Q_PROPERTY(int ProtocolVersion READ protocolVersion)
    Q_PROPERTY(int Orientation READ orientation)
    Q_PROPERTY(int ContentOrientation READ contentOrientation)
    Q_PROPERTY(bool Active READ active)
    Q_PROPERTY(int CoverStatus READ coverStatus)
    Q_PROPERTY(QVariantMap Ambience READ ambience)
    Q_PROPERTY(int Dpi READ dpi)

public:
    int protocolVersion() const { return 1; }
    int orientation() const { return m_orientation; }
    int contentOrientation() const;
    bool active() const { return m_active; }
    int coverStatus() const { return m_coverStatus; }
    QVariantMap ambience() const { return m_ambience; }
    int dpi() const { return 401; }

    // Test-side view (thread-safe).
    int activateCalls() const;
    QList<int> contentOrientations() const;

public slots:
    Q_SCRIPTABLE QString Ping() { return QStringLiteral("keel-shell"); }
    Q_SCRIPTABLE QVariantMap GetAmbience() { return m_ambience; }
    Q_SCRIPTABLE void Activate();
    Q_SCRIPTABLE void SetContentOrientation(int degrees);

    // Driven from the test thread with queued invocations.
    void setOrientation(int degrees);
    void setActive(bool active);
    void setCoverStatus(int status);
    void setAmbience(const QVariantMap &ambience);
    void requestClose();

signals:
    Q_SCRIPTABLE void OrientationChanged(int degrees);
    Q_SCRIPTABLE void ContentOrientationChanged(int degrees);
    Q_SCRIPTABLE void ActiveChanged(bool active);
    Q_SCRIPTABLE void CoverStatusChanged(int status);
    Q_SCRIPTABLE void AmbienceChanged(const QVariantMap &ambience);
    Q_SCRIPTABLE void DpiChanged(int dpi);
    Q_SCRIPTABLE void CloseRequested();

private:
    mutable QMutex m_mutex;
    int m_orientation = 0;
    bool m_active = true;
    int m_coverStatus = 0;
    QVariantMap m_ambience;
    int m_activateCalls = 0;
    QList<int> m_contentOrientations;
};

class FakeShell : public QObject
{
    Q_OBJECT
public:
    // Starts the server thread and returns once it listens.
    explicit FakeShell(const QString &socketDir);
    ~FakeShell() override;

    QString address() const { return m_address; }
    FakeShellObject *object() const { return m_object; }
    bool clientConnected() const;

private:
    QThread m_thread;
    QObject *m_context = nullptr;
    QDBusServer *m_server = nullptr;
    FakeShellObject *m_object = nullptr;
    QString m_address;
    mutable QMutex m_mutex;
    bool m_connected = false;
};

#endif
