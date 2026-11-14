// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Fake D-Bus services for the nemo-compat tests, run in their own thread on
// their own connection to the private test bus:
//   org.freedesktop.Notifications  (Desktop Notifications spec + the Nemo
//                                   GetNotifications extension)
//   com.nokia.mce                  (the request/signal calls nemo-keepalive uses)
//   org.shipwright.test            (an echo service for DBusInterface)
//   com.nokia.NonGraphicFeedback1.Backend  (ngfd: Play, Pause, Stop)
// Every incoming call is recorded; tests poll the records and emit signals.
#ifndef KEEL_TEST_FAKESERVICES_H
#define KEEL_TEST_FAKESERVICES_H

#include <QDBusConnection>
#include <QDBusMessage>
#include <QMutex>
#include <QThread>
#include <QVariantList>

struct RecordedCall
{
    QString path;
    QString interface;
    QString member;
    QVariantList arguments;
};

class FakeServices : public QObject
{
    Q_OBJECT
public:
    explicit FakeServices(const QString &busAddress);
    ~FakeServices() override;

    bool ready() const { return m_ready; }
    QList<RecordedCall> calls(const QString &member = QString()) const;
    void clearCalls();
    void record(const QDBusMessage &message);

    // Emits a signal from the fake services' connection.
    void emitSignal(const QString &path, const QString &interface, const QString &name,
                    const QVariantList &arguments) const;

    // Signals other clients emitted (for DBusAdaptor.emitSignal).
    QList<RecordedCall> observedSignals() const;

    // Calls a method from the fake connection without blocking this thread.
    QDBusPendingCall asyncCall(const QString &service, const QString &path, const QString &interface,
                               const QString &method, const QVariantList &arguments) const;

    QDBusConnection connection() const;

    QString displayStatus = QStringLiteral("on");

private slots:
    void onObservedSignal(const QDBusMessage &message);

private:
    QThread m_thread;
    QObject *m_context = nullptr;
    QList<QObject *> m_objects;
    QString m_connectionName;
    bool m_ready = false;
    mutable QMutex m_mutex;
    QList<RecordedCall> m_calls;
    QList<RecordedCall> m_signals;
};

#endif
